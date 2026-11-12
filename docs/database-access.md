# Human access to the PROD databases

**Audience:** developers and platform engineers who need to query a PROD PostgreSQL instance

The PROD databases are private and stay private. You reach them through an AWS Systems Manager (SSM) Session Manager port-forwarding tunnel to a small jump instance inside the VPC. Nothing listens on the internet, and there is no SSH key. Your IAM Identity Center sign-in decides whether you can open the tunnel and which database password you can read.

```
your laptop :15432 ──(Session Manager, IAM-checked)──▶ jump instance ──▶ <database>:5432
```

All of this lives in `database-access.tf` and is switched on by `enable_database_access = true` in `env/prod.tfvars`.

## Access tiers

| Tier | IAM policy (customer-managed, PROD account) | Can read | Logs in to Postgres as |
|---|---|---|---|
| Admin | `aiae-operational-hub-prod-database-admin-access` | The RDS-managed master secret and the `db-readonly` secret of every database | Master user (full rights) |
| Read-only | `aiae-operational-hub-prod-database-readonly-access` | `<app prefix>/db-readonly` secrets only | `readonly` (read-only) |

Both tiers can open a port-forwarding tunnel to the jump instance only. They cannot open a shell on it.

The per-database values come from `terraform output database_access_targets`:

| Key | Read-only secret |
|---|---|
| `operational-hub` | `AIAE-PRD/operational-hub/db-readonly` |
| `onboarding` | `AIAE-PRD/aiae-onboarding/db-readonly` |
| `paicing` | `AIAE-PRD/aiae-paicing/db-readonly` |
| `presentation-builder` | `AIAE-PRD/aiae-presentation-builder/db-readonly` (only when enabled) |

## Granting a person access

Policies cannot be attached directly to Identity Center's `AWSReservedSSO_*` roles. Do it in IAM Identity Center.

Use the **organization instance** `ssoins-722356da9180bb25`, managed from the management account `389473156764`. Its user directory is `d-906626d776` and its portal is `https://d-906626d776.awsapps.com/start`. Do not use the PROD account instance `ssoins-7223b53871c5ac5f`, which Grafana and Argo CD use. It holds a separate set of users and can only assign applications, not AWS accounts.

One-time setup (already described step by step for whoever administers Identity Center):

1. Create the groups `aiae-db-readonly` and `aiae-db-admins`.
2. Create two custom permission sets with an 8-hour session. Each attaches one **customer managed policy** (path `/`):

   | Permission set | Customer managed policy |
   | --- | --- |
   | `AIAE-DB-ReadOnly` | `aiae-operational-hub-prod-database-readonly-access` |
   | `AIAE-DB-Admin` | `aiae-operational-hub-prod-database-admin-access` |

3. Under **AWS accounts**, select only `125093118532` and assign `aiae-db-readonly` → `AIAE-DB-ReadOnly` and `aiae-db-admins` → `AIAE-DB-Admin`. DEV does not have these policies, so an assignment there fails.

After that, granting access means adding the person to the right group, and revoking it means removing them.

To revoke access, remove them from the group. That closes off the tunnel and the secret straight away. The person may still know a password they fetched earlier, but it is useless without the tunnel. To invalidate it anyway:

- **Admin password.** RDS rotates it every 7 days. To rotate it now, run `aws rds modify-db-instance --db-instance-identifier <id> --rotate-master-user-password --apply-immediately`.
- **Read-only password.** It is never rotated automatically. Rotate it as described in the setup section below.

## Connecting

The step-by-step guide for users is in the [README, "PROD database access"](../README.md#prod-database-access). It covers signing in with Identity Center or `aws login`, the tunnel, the credentials, the hosts per application, and using the read-only login.

## One-time setup: the read-only Postgres role (admin)

Terraform creates each `db-readonly` secret empty. It never writes the password, so the password never reaches Terraform state. An admin does the following once per database, through the tunnel, connected as the master user (see the README for opening the tunnel):

```bash
PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

psql "host=localhost port=15432 dbname=<db_name> user=<master user> sslmode=require" <<SQL
CREATE ROLE readonly LOGIN PASSWORD '$PASSWORD';
GRANT CONNECT ON DATABASE <db_name> TO readonly;
GRANT pg_read_all_data TO readonly;          -- SELECT on all current and future tables
ALTER ROLE readonly SET default_transaction_read_only = on;
SQL

aws secretsmanager put-secret-value --secret-id AIAE-PRD/<app>/db-readonly \
  --secret-string "{\"username\":\"readonly\",\"password\":\"$PASSWORD\"}"
```

To rotate the password, run `ALTER ROLE readonly PASSWORD '...'` and `put-secret-value` again.

## Guarantees and limits

- The jump instance has no inbound rules, no public IP, and requires IMDSv2. Its egress allows only PostgreSQL inside the VPC and HTTPS to the SSM endpoints. That egress rule is what keeps tunnels limited to the databases, because Session Manager cannot restrict which host a port-forward targets.
- The `ssm:SessionDocumentAccessCheck` condition blocks the default shell document, so the policies allow port forwarding only.
- Every session start and every secret read is recorded in CloudTrail with the caller's Identity Center identity.
- The jump instance's AMI is pinned by `ignore_changes`. To pick up a new Amazon Linux 2023 image, run `terraform apply -replace=aws_instance.database_access[0]`.
