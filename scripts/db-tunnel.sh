#!/usr/bin/env bash
# Open an SSM tunnel to a PROD PostgreSQL database through the jump instance.
# It does not connect to the database: point psql, DataGrip, IntelliJ or
# pgAdmin at the printed host/port. Ctrl+C closes the tunnel.
#
#   scripts/db-tunnel.sh <database> [options]
#
# Works on Linux, macOS and Windows (Git Bash / WSL). See README.md,
# "PROD database access", for signing in to AWS first.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/db-tunnel.sh <database> [options]

Opens a tunnel 127.0.0.1:<port> -> <database>:5432 and keeps it open until
Ctrl+C. It does not connect to the database itself.

Databases:
  operational-hub   Operational Hub       (default local port 15432)
  onboarding        Onboarding Platform   (default local port 15433)
  pacing            Pacing                (default local port 15434)

Options:
  --role <role>     Which credentials to print: readonly (default) or admin.
                      readonly: user `readonly`, SELECT only
                                (AIAE-DB-ReadOnly or AIAE-DB-Admin permission set).
                      admin:    the RDS master user, full rights
                                (AIAE-DB-Admin permission set or AWS admin).
  --readonly        Same as --role readonly.
  --admin           Same as --role admin.
  --copy-password   Also copy the printed password to the clipboard.
  --port <n>        Local port (default: per database, see above).
  --profile <name>  AWS CLI profile (default: $AWS_PROFILE).
  -h, --help        Show this help.

Examples:
  scripts/db-tunnel.sh operational-hub
  scripts/db-tunnel.sh operational-hub --role admin --copy-password
  scripts/db-tunnel.sh pacing --port 25432 --profile aiae-prod-db
EOF
}

die() { echo "error: $*" >&2; exit 1; }

# --- Arguments ----------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac

DB_KEY=$1; shift
case "$DB_KEY" in
  operational-hub|operational_hub|ophub)
    DB_KEY=operational-hub; RDS_ID=aiae-operational-hub-prod-postgres
    RO_SECRET=AIAE-PRD/operational-hub/db-readonly; PORT=15432 ;;
  onboarding)
    RDS_ID=aiae-onboarding-prod-postgres
    RO_SECRET=AIAE-PRD/aiae-onboarding/db-readonly; PORT=15433 ;;
  pacing|paicing)
    DB_KEY=pacing; RDS_ID=aiae-paicing-prod-postgres
    RO_SECRET=AIAE-PRD/aiae-paicing/db-readonly; PORT=15434 ;;
  *) die "unknown database '$DB_KEY' (operational-hub | onboarding | pacing)" ;;
esac

ROLE=readonly COPY_PASSWORD=false
while [ $# -gt 0 ]; do
  case "$1" in
    --role)          [ $# -ge 2 ] || die "--role needs a value"; ROLE=$2; shift ;;
    --admin)         ROLE=admin ;;
    --readonly)      ROLE=readonly ;;
    --copy-password) COPY_PASSWORD=true ;;
    --port)          [ $# -ge 2 ] || die "--port needs a value"; PORT=$2; shift ;;
    --profile)       [ $# -ge 2 ] || die "--profile needs a value"; export AWS_PROFILE=$2; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option '$1' (see --help)" ;;
  esac
  shift
done

case "$ROLE" in
  readonly|read-only|ro) ROLE=readonly ;;
  admin|master|rw)       ROLE=admin ;;
  *) die "unknown role '$ROLE' (readonly | admin)" ;;
esac

export AWS_REGION=${AWS_REGION:-us-east-1}
JUMP_NAME=aiae-operational-hub-prod-database-access

# --- Tools --------------------------------------------------------------------
# Git Bash on Windows: pick up default install locations if not on PATH.
for d in "/c/Program Files/Amazon/SessionManagerPlugin/bin" "/c/Program Files/Amazon/AWSCLIV2"; do
  [ -d "$d" ] && PATH="$PATH:$d"
done
command -v aws >/dev/null 2>&1 || die "AWS CLI v2 not found"
command -v session-manager-plugin >/dev/null 2>&1 || die "Session Manager plugin not found (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)"

# --- AWS identity -------------------------------------------------------------
if ! IDENTITY=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
  die "not signed in to AWS. Run 'aws sso login --profile <profile>' or 'aws login --profile <profile>' (and set AWS_PROFILE or pass --profile)"
fi
echo "AWS identity: $(tr -d '\r' <<<"$IDENTITY")"

# --- Resolve database and jump instance ----------------------------------------
read -r DB_HOST DB_NAME MASTER_ARN < <(aws rds describe-db-instances --db-instance-identifier "$RDS_ID" \
  --query 'DBInstances[0].[Endpoint.Address,DBName,MasterUserSecret.SecretArn]' --output text 2>/dev/null | tr -d '\r') || true
[ -n "${DB_HOST:-}" ] && [ "$DB_HOST" != None ] || die "cannot describe $RDS_ID (does your role allow rds:DescribeDBInstances?)"

JUMP_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$JUMP_NAME" Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text | tr -d '\r')
[ -n "$JUMP_ID" ] && [ "$JUMP_ID" != None ] || die "jump instance $JUMP_NAME not found or not running"

if [ "$ROLE" = admin ]; then SECRET_ID=$MASTER_ARN; else SECRET_ID=$RO_SECRET; fi

# --- Credentials ----------------------------------------------------------------
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text 2>/dev/null) || {
  if [ "$ROLE" = admin ]; then
    die "cannot read the admin credentials: needs the AIAE-DB-Admin permission set (or AWS admin); use --role readonly otherwise"
  else
    die "cannot read the readonly credentials from $SECRET_ID: needs the AIAE-DB-ReadOnly or AIAE-DB-Admin permission set"
  fi
}
json_field() {  # json_field <field>  (JSON on stdin); jq if present, else Python, else sed
  if command -v jq >/dev/null 2>&1; then jq -r --arg f "$1" '.[$f]'
  else
    for py in python3 python; do
      if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import json' >/dev/null 2>&1; then
        "$py" -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; return
      fi
    done
    sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"
  fi
}
DB_USER=$(json_field username <<<"$SECRET_JSON" | tr -d '\r')

# --- Tunnel ---------------------------------------------------------------------
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  die "local port $PORT is already in use (another tunnel?). Use --port <n>."
fi

WORK=$(mktemp -d)
TUNNEL_PID="" SESSION_ID=""
cleanup() {
  unset SECRET_JSON
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null && wait "$TUNNEL_PID" 2>/dev/null
  [ -n "$SESSION_ID" ] && aws ssm terminate-session --session-id "$SESSION_ID" >/dev/null 2>&1
  rm -rf "$WORK"
  echo "Tunnel closed."
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "Opening tunnel: 127.0.0.1:$PORT -> $DB_HOST:5432 via $JUMP_ID"
aws ssm start-session --target "$JUMP_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=$DB_HOST,portNumber=5432,localPortNumber=$PORT" \
  >"$WORK/ssm.log" 2>&1 &
TUNNEL_PID=$!

for _ in $(seq 1 30); do
  grep -q "Waiting for connections" "$WORK/ssm.log" 2>/dev/null && break
  kill -0 "$TUNNEL_PID" 2>/dev/null || { cat "$WORK/ssm.log" >&2; die "tunnel failed to start"; }
  sleep 1
done
grep -q "Waiting for connections" "$WORK/ssm.log" || { cat "$WORK/ssm.log" >&2; die "tunnel did not become ready"; }
SESSION_ID=$(grep -o 'SessionId: [^ .]*' "$WORK/ssm.log" | head -1 | cut -d' ' -f2 || true)

# --- Connection details -------------------------------------------------------
cat <<EOF

Tunnel is open ($DB_KEY, role: $ROLE). Connect your client with:
  Host:     127.0.0.1
  Port:     $PORT
  Database: $DB_NAME
  User:     $DB_USER
  SSL mode: require
EOF

DB_PASS=$(json_field password <<<"$SECRET_JSON" | tr -d '\r\n')
unset SECRET_JSON
echo "  Password: $DB_PASS"

if $COPY_PASSWORD; then
  copied=true
  if   command -v clip.exe >/dev/null 2>&1; then printf %s "$DB_PASS" | clip.exe
  elif command -v pbcopy   >/dev/null 2>&1; then printf %s "$DB_PASS" | pbcopy
  elif command -v wl-copy  >/dev/null 2>&1; then printf %s "$DB_PASS" | wl-copy
  elif command -v xclip    >/dev/null 2>&1; then printf %s "$DB_PASS" | xclip -selection clipboard
  else copied=false; fi
  if $copied; then echo "            (also copied to clipboard)"
  else echo "            (no clipboard tool found)"; fi
fi
unset DB_PASS

cat <<EOF

  psql "host=127.0.0.1 port=$PORT dbname=$DB_NAME user=$DB_USER sslmode=require"
EOF
if [ "$ROLE" = admin ]; then
  echo
  echo "WARNING: admin credentials are the master user: writes are allowed. Prefer --role readonly for reading."
fi
echo
echo "Press Ctrl+C to close the tunnel."
wait "$TUNNEL_PID" || true
