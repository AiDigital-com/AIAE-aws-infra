# AIAE AWS Infrastructure

Terraform for the shared AIAE AWS platform. Operational Hub is the first application; additional AIAE applications can be added without creating new infrastructure repositories.

## Repository boundaries

- This repository owns AWS infrastructure and EKS/Argo CD bootstrap resources.
- `AIAE-helm` owns reusable application Helm charts.
- `AIAE-helm-versions` owns environment values and deployed image tags.
- Each application repository owns build/test, Maven Liquibase, image push, and the GitOps tag update.

## Accounts

| Environment | AWS account | Region | Terraform profile |
| --- | --- | --- | --- |
| dev | `496336474487` | `us-east-1` | `aiae-dev` |
| prod | `125093118532` | `us-east-1` | `aiae-prod` |

Every account has independent VPC, EKS, ECR, RDS, Secrets Manager, GitHub OIDC, CodeConnections, and Terraform state resources. Nothing is shared across the dev/prod account boundary.

## Operational Hub resources

Each environment stack creates:

- VPC with public, private, and database subnets, NAT gateways, and VPC flow logs.
- EKS Auto Mode with control-plane CloudWatch logs and IRSA enabled.
- RDS PostgreSQL with managed master credentials, environment-specific network access and backups, log exports, and alarms.
- ECR repository `aidigital.aiae-projects/operational-hub-application`.
- Secrets Manager container `AIAE-DEV/operational-hub` or `AIAE-PRD/operational-hub`.
- Application IAM role restricted to the environment secret.
- Secrets Store CSI driver/provider with Kubernetes Secret synchronization and rotation.
- EKS Auto Mode ALB `IngressClass` and `IngressClassParams`.
- GitHub Actions OIDC role restricted to ECR image push.

Optional feature flags add:

- AWS-managed Argo CD capability with Identity Center mappings.
- GitHub CodeConnections authentication and Argo CD GitOps bootstrap.
- ACM certificate, Route53 DNS validation, and ExternalDNS when a Route53 zone is available.
- Private S3 + CloudFront frontend hosting.
- Application stdout delivery to CloudWatch Logs through AWS for Fluent Bit. It is enabled only in PROD and retains logs for one day.

## Prerequisites

- Terraform 1.10 or newer for native S3 state locking.
- AWS CLI v2, because the Helm provider uses `aws eks get-token`.
- CLI profiles `aiae-dev` and `aiae-prod`, preferably backed by IAM Identity Center.
- Platform-provisioning permissions in both accounts.

No AWS access keys are stored in GitHub. GitHub Actions assumes Terraform-created roles through OIDC.

## 1. Bootstrap remote state

Bootstrap each account independently. The explicit account ID and profile prevent applying to the wrong account.

```bash
cd bootstrap

AWS_PROFILE=aiae-dev terraform init
AWS_PROFILE=aiae-dev terraform workspace select -or-create dev
AWS_PROFILE=aiae-dev terraform plan -var-file=env/dev.tfvars
AWS_PROFILE=aiae-dev terraform apply -var-file=env/dev.tfvars

AWS_PROFILE=aiae-prod terraform workspace select -or-create prod
AWS_PROFILE=aiae-prod terraform plan -var-file=env/prod.tfvars
AWS_PROFILE=aiae-prod terraform apply -var-file=env/prod.tfvars

cd ..
```

This creates one state bucket per account. The root backend files enable native
S3 lockfiles, so concurrent Terraform writes are rejected without a separate
DynamoDB table.

## 2. Apply base infrastructure

Dev:

```bash
AWS_PROFILE=aiae-dev terraform init -reconfigure -backend-config=backend-config/dev.hcl
AWS_PROFILE=aiae-dev terraform plan -var-file=env/dev.tfvars
AWS_PROFILE=aiae-dev terraform apply -var-file=env/dev.tfvars
```

Prod:

```bash
AWS_PROFILE=aiae-prod terraform init -reconfigure -backend-config=backend-config/prod.hcl
AWS_PROFILE=aiae-prod terraform plan -var-file=env/prod.tfvars
AWS_PROFILE=aiae-prod terraform apply -var-file=env/prod.tfvars
```

The initial base apply leaves Argo CD, DNS, and frontend flags disabled until their external inputs are available.

DEV RDS is publicly reachable only from the CIDRs listed in
`database_public_access_cidrs` and has automated backups disabled. Update the
`/32` entry in `env/dev.tfvars` when the developer's public IP changes. PROD
RDS remains private, Multi-AZ, and retains automated backups for 14 days.

## 3. Configure GitHub and Argo CD

In each account, set `create_github_codeconnection = true` and apply once. AWS creates the connection in `PENDING`; complete its GitHub authorization in the AWS CodeConnections console. Terraform cannot complete that OAuth handshake.

Get the IAM Identity Center instance ARN and group/user IDs, then configure the matching environment:

```hcl
enable_argocd           = true
enable_gitops_bootstrap = true
argocd_idc_instance_arn = "arn:aws:sso:::instance/ssoins-..."

argocd_rbac_role_mappings = {
  platform_admins = {
    role = "ADMIN"
    identities = [{
      id   = "identity-center-group-id"
      type = "SSO_GROUP"
    }]
  }
}
```

The capability role receives only `GetConnection` and `UseConnection` for its account's connection. Terraform then creates the managed Argo CD capability, registers the local EKS cluster, and creates the environment AppProject and Application.

## 4. DNS and TLS

The current domain is managed in GoDaddy, not Route53, so Route53 and ExternalDNS remain disabled. For manual validation:

1. Set `frontend_certificate_request_domain_name` while leaving `frontend_domain_name` empty, then apply Terraform.
2. Add the CNAME from `frontend_certificate_validation_options` in GoDaddy and wait for ACM status `ISSUED`.
3. Set `frontend_domain_name` to the same hostname and apply Terraform again.
4. Add the application CNAME in GoDaddy, pointing the hostname to the `frontend_url` CloudFront distribution hostname.

Alternatively, delegate an AIAE subdomain to Route53 and enable the existing Terraform DNS resources. DEV uses its generated CloudFront hostname and does not depend on the production GoDaddy zone.

## 5. Populate application secrets

Terraform creates the secret container but never writes secret values into Terraform state. Populate each environment secret as JSON:

```json
{
  "POSTGRES_HOST": "database-host",
  "POSTGRES_PORT": "5432",
  "POSTGRES_DB": "operational_hub",
  "POSTGRES_USER": "operational_hub",
  "POSTGRES_PASSWORD": "database-password",
  "CLERK_PUBLISHABLE_KEY": "pk_test_or_live_value",
  "CLERK_SECRET_KEY": "clerk-secret-key",
  "GOOGLE_SERVICE_ACCOUNT_JSON": "{}"
}
```

Use these Terraform outputs:

- `rds_endpoint`
- `rds_port`
- `rds_master_user_secret_arn`
- `secrets_manager_secret_name`
- `application_iam_role_arn`

The deterministic application role ARN is stored in the matching `AIAE-helm`
environment branch. Verify it against `application_iam_role_arn` before enabling
the Argo CD bootstrap.

## 6. Configure GitHub Actions

Create GitHub environments `dev` and `prod` in each application repository with:

- `AWS_REGION=us-east-1`
- `AWS_ROLE_TO_ASSUME=<github_backend_ci_role_arn>`
- `APP_CONFIG_SECRET_NAME=AIAE-DEV/operational-hub` for DEV or `AIAE-PRD/operational-hub` for PROD
- `FRONTEND_BUCKET=<frontend_bucket_name>`
- `FRONTEND_DISTRIBUTION_ID=<frontend_cloudfront_distribution_id>`
- `GITOPS_VERSIONS_REPOSITORY=AiDigital-com/AIAE-helm-versions`
- `GITOPS_HELM_REPOSITORY=AiDigital-com/AIAE-helm`
- secret `GITOPS_TOKEN`

No `GITOPS_DEPLOY_ENABLED` flag is required. DEV deployment is limited to pushes
to version branches, while PROD is manual and can be protected with GitHub
Environment reviewers.

## Liquibase migration

The application pipeline publishes a Maven-based Liquibase image beside the
application image. The Operational Hub chart runs it as an Argo CD Sync hook
inside EKS before the Deployment sync wave. The hook reads the matching
Secrets Manager object through IRSA and blocks the rollout when migration
fails.

## Optional frontend

`enable_frontend = true` creates a private S3 bucket and CloudFront distribution. Leave `frontend_domain_name` empty to use the generated CloudFront hostname. `frontend_certificate_request_domain_name` can request a certificate without attaching it while external DNS validation is pending. A custom frontend hostname must differ from the API/ALB hostname.

## PROD database access

The PROD databases are private: there is no public endpoint and no open port. You reach them from your machine through an **SSM Session Manager port-forwarding tunnel** to a jump instance inside the VPC. You need an AWS sign-in that is allowed to open the tunnel and to read the database credentials.

```
your machine 127.0.0.1:15432 ──(SSM, IAM-checked)──▶ jump instance ──▶ <database>:5432
```

All commands in this section are bash. On Windows, run them in Git Bash or WSL.

The infrastructure is defined in `database-access.tf` and enabled by `enable_database_access = true` in `env/prod.tfvars`. Admin tasks (granting access, creating or re-keying the read-only login, rotating passwords) are in [docs/database-access.md](docs/database-access.md).

### Databases

All instances are PostgreSQL 16 in account `125093118532`, region `us-east-1`.

| Application | RDS instance | Host | Database | Master user | Read-only secret |
| --- | --- | --- | --- | --- | --- |
| Operational Hub | `aiae-operational-hub-prod-postgres` | `aiae-operational-hub-prod-postgres.c0ngq6aam0o8.us-east-1.rds.amazonaws.com` | `operational_hub` | `operational_hub` | `AIAE-PRD/operational-hub/db-readonly` |
| Onboarding Platform | `aiae-onboarding-prod-postgres` | `aiae-onboarding-prod-postgres.c0ngq6aam0o8.us-east-1.rds.amazonaws.com` | `aionboarding` | `aionboarding` | `AIAE-PRD/aiae-onboarding/db-readonly` |
| Pacing | `aiae-paicing-prod-postgres` | `aiae-paicing-prod-postgres.c0ngq6aam0o8.us-east-1.rds.amazonaws.com` | `pacing` | `pacing` | `AIAE-PRD/aiae-paicing/db-readonly` |

Presentation Builder is not enabled in PROD. When it is, it gets the same setup under `AIAE-PRD/aiae-presentation-builder/db-readonly`.

Current values are always available from Terraform:

```bash
terraform output database_access_targets       # host + master secret ARN + read-only secret per database
terraform output database_access_instance_id   # jump instance
```

### Access tiers

| Tier | Who | Logs in to Postgres as | Credentials secret |
| --- | --- | --- | --- |
| **Read-only** (default) | Anyone who needs to look at data | `readonly` | `AIAE-PRD/<app>/db-readonly` |
| **Admin** | The few people who must change data | the master user (full rights) | RDS-managed master secret; the password rotates every 7 days |

Both tiers can open the tunnel to the jump instance only, not a shell on it. Every tunnel and every secret read is recorded in CloudTrail under your identity.

### Quick start: open a tunnel with the script

After signing in (step 1), one command opens the tunnel and prints the connection details, including the password. It does **not** connect to the database: you connect with psql, DataGrip, IntelliJ or pgAdmin. Ctrl+C closes the tunnel and its SSM session. Use `scripts/db-tunnel.sh` on Linux, macOS, Git Bash or WSL, and `scripts/db-tunnel.ps1` in Windows PowerShell.

```bash
export AWS_PROFILE=aiae-prod-db          # or pass --profile

scripts/db-tunnel.sh operational-hub     # 127.0.0.1:15432, readonly credentials
scripts/db-tunnel.sh onboarding          # 127.0.0.1:15433
scripts/db-tunnel.sh pacing              # 127.0.0.1:15434

scripts/db-tunnel.sh operational-hub --role readonly --copy-password   # also copy the password to the clipboard
scripts/db-tunnel.sh operational-hub --role admin                      # master user details (or: --admin)
```

```powershell
.\scripts\db-tunnel.ps1 operational-hub -AwsProfile aiae-prod-db
.\scripts\db-tunnel.ps1 pacing -Role readonly -CopyPassword
.\scripts\db-tunnel.ps1 pacing -Role admin                  # or: -Admin
```

If PowerShell refuses to run scripts, start it with `powershell -ExecutionPolicy Bypass -File .\scripts\db-tunnel.ps1 operational-hub`.

Example output:

```
Tunnel is open (operational-hub, role: readonly). Connect your client with:
  Host:     127.0.0.1
  Port:     15432
  Database: operational_hub
  User:     readonly
  SSL mode: require
  Password: <printed here>

  psql "host=127.0.0.1 port=15432 dbname=operational_hub user=readonly sslmode=require"

Press Ctrl+C to close the tunnel.
```

| Option (bash / PowerShell) | Effect |
| --- | --- |
| `--role readonly` / `-Role readonly` (default; also `--readonly` / `-ReadOnly`) | Prints the credentials of user `readonly` (SELECT only). Works with the `AIAE-DB-ReadOnly` or `AIAE-DB-Admin` permission set. |
| `--role admin` / `-Role admin` (also `--admin` / `-Admin`) | Prints the credentials of the RDS master user (full rights). Needs the `AIAE-DB-Admin` permission set or AWS admin. |
| `--copy-password` / `-CopyPassword` | Also puts the printed password on the clipboard. |
| `--port <n>` / `-Port <n>` | Local port. Defaults: 15432 operational-hub, 15433 onboarding, 15434 pacing, so all three can be open at once. |
| `--profile <p>` / `-AwsProfile <p>` | AWS CLI profile. Default: `AWS_PROFILE`. |

The role decides only which credentials are printed. The tunnel is the same for both. The password stays in your terminal's scrollback: clear the screen when you are done, especially after an admin session, and don't share the terminal output or screenshots of it. The scripts need the AWS CLI v2 and the Session Manager plugin. The steps below do the same thing by hand.

### Step 1: Sign in to AWS

Choose the method that matches how you were given access.

#### Option A: Identity Center user (recommended for everyone)

Access is granted by membership of the Identity Center group `aiae-db-readonly` or `aiae-db-admins` in the organization's directory. That directory is **not** the one used for Grafana or Argo CD, so you need its own invite.

First time:

1. Accept the email "Invitation to join AWS IAM Identity Center". Set a password and enrol MFA.
2. Open the access portal at `https://d-906626d776.awsapps.com/start`. Account `125093118532` should be listed with the role `AIAE-DB-ReadOnly` or `AIAE-DB-Admin`.
3. Install the [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (`winget install Amazon.SessionManagerPlugin` on Windows), and a SQL client: `psql`, DataGrip, IntelliJ or pgAdmin.
4. Create a CLI profile:

   ```bash
   aws configure sso --profile aiae-prod-db
   ```

   | Prompt | Answer |
   | --- | --- |
   | SSO session name | `aidigital` |
   | SSO start URL | `https://d-906626d776.awsapps.com/start` |
   | SSO region | `us-east-1` |
   | SSO registration scopes | press Enter |
   | (browser opens: approve) | |
   | Account | `125093118532` |
   | Role | `AIAE-DB-ReadOnly` or `AIAE-DB-Admin` |
   | Default client Region | `us-east-1` |
   | CLI default output format | press Enter |

Every day (one sign-in lasts the 8-hour session):

```bash
aws sso login --profile aiae-prod-db
export AWS_PROFILE=aiae-prod-db
```

#### Option B: IAM user in the PROD account (platform admins)

This is for people who sign in to the PROD console with an IAM user, such as `Admin`. It gives short-lived CLI credentials and needs no access keys.

```bash
aws login --profile aiae-prod --region us-east-1
aws configure set region us-east-1 --profile aiae-prod   # once
export AWS_PROFILE=aiae-prod
```

To sign in as a different IAM user than the browser's current console session, sign out of the console first. Or run `aws login --profile <name> --remote`, open the printed URL in a private window, and sign in at `https://125093118532.signin.aws.amazon.com/console`.

Check who you are before going further:

```bash
aws sts get-caller-identity     # Account must be 125093118532
```

### Step 2: Open the tunnel

Leave this running in its own terminal. Wait for `Waiting for connections...`.

```bash
JUMP=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=aiae-operational-hub-prod-database-access Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ssm start-session --target "$JUMP" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters 'host=aiae-operational-hub-prod-postgres.c0ngq6aam0o8.us-east-1.rds.amazonaws.com,portNumber=5432,localPortNumber=15432'
```

Replace the `host` with the database you need, from the table above. To use several databases at once, run one tunnel per database on different local ports, for example:

| Local port | Database |
| --- | --- |
| `15432` | Operational Hub |
| `15433` | Onboarding Platform |
| `15434` | Pacing |

Press Ctrl+C to close the tunnel when you are done. The jump instance is currently `i-021cc1457c26e0571`, but look it up as above, because it changes if the instance is replaced.

### Step 3: Get the credentials

Read-only (use this unless you must write):

```bash
aws secretsmanager get-secret-value --secret-id AIAE-PRD/operational-hub/db-readonly   --query SecretString --output text
# {"username": "readonly", "password": "...", "dbname": "operational_hub"}
```

Admin (master user):

```bash
ARN=$(aws rds describe-db-instances --db-instance-identifier aiae-operational-hub-prod-postgres   --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
aws secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text
```

The master password rotates every 7 days. Fetch it fresh each time, and update saved IDE passwords after a rotation.

### Step 4: Connect

psql:

```bash
psql "host=127.0.0.1 port=15432 dbname=operational_hub user=readonly sslmode=require"
```

Or let psql take the password straight from the secret, without it appearing on screen (needs `jq`):

```bash
SECRET=$(aws secretsmanager get-secret-value --secret-id AIAE-PRD/operational-hub/db-readonly   --query SecretString --output text)
PGPASSWORD=$(jq -r .password <<<"$SECRET")   psql "host=127.0.0.1 port=15432 dbname=$(jq -r .dbname <<<"$SECRET") user=readonly sslmode=require"
unset SECRET
```

IntelliJ / DataGrip / pgAdmin: create a PostgreSQL data source with:

| Setting | Value |
| --- | --- |
| Host | `127.0.0.1` |
| Port | `15432` (or the local port of that database's tunnel) |
| Database | `operational_hub`, `aionboarding` or `pacing` |
| User / password | from step 3 |
| SSL mode | `require` |

The IDE cannot start the SSM tunnel itself, so open the tunnel (step 2) first.

Use `sslmode=require`, not `verify-full`. The RDS certificate is issued for the RDS hostname, not for `127.0.0.1`. The connection is still encrypted end to end.

#### DBeaver

DBeaver connects through the tunnel like any local PostgreSQL server. Create one connection per database and role, for example `PROD operational-hub (readonly)`, each on its database's local port.

1. Open the tunnel first. It prints the user and password:

   ```bash
   scripts/db-tunnel.sh operational-hub --copy-password
   ```

2. **Database → New Database Connection → PostgreSQL → Next.**
3. **Main** tab:

   | Field | Value |
   | --- | --- |
   | Connect by | Host |
   | Host | `127.0.0.1` (not `localhost`, which may resolve to IPv6 `::1`, where the tunnel does not listen) |
   | Port | `15432` operational-hub, `15433` onboarding, `15434` pacing |
   | Database | `operational_hub`, `aionboarding` or `pacing` |
   | Authentication | Database Native |
   | Username | `readonly`, or the master user for admin (`operational_hub`, `aionboarding`, `pacing`) |
   | Password | As printed by the tunnel script (or `--copy-password` to paste it), or from step 3 |
   | Save password | On for `readonly` (its password changes only when an admin re-keys it). **Off** for admin, because the master password rotates every 7 days. |

4. **SSL** tab: tick **Use SSL** and set **SSL mode** to `require`. Leave the root certificate, client certificate and key empty. In older DBeaver versions without an SSL mode field, add the driver property `sslmode` = `require` on the **Driver properties** tab instead.
5. **PostgreSQL** tab: leave **Show all databases** off. The role can only connect to its own database.
6. **Connection details (name, type)**, at the bottom left of the wizard:
   - **Connection name:** for example `PROD operational-hub (readonly)`.
   - **Connection type:** **Production**. DBeaver then colours the editor red, asks for confirmation before running data-modifying SQL, and turns auto-commit off by default.
   - **Security → Read-only connection:** tick it for `readonly` connections, so DBeaver also blocks edits in the data grid. For admin connections, leave it unticked only when you really intend to write.
7. **Test Connection** → **Finish**. If DBeaver offers to download the PostgreSQL driver, accept.

Day to day: start the tunnel script, then connect in DBeaver. When you stop the tunnel, DBeaver shows `Connection refused`; start the tunnel again and use **Invalidate/Reconnect**.

Tips for DBeaver on PROD:

- **Set a query timeout for every session:** connection → **Edit Connection → Connection settings → Initialization → Bootstrap queries → Configure**, then add `SET statement_timeout = '60s'`. Or run it once in the SQL editor.
- **Keep auto-commit on for readonly connections.** If you turn it off, end transactions promptly (**Commit** / **Rollback**) so you don't hold locks or block vacuum.
- **Export data** with right-click on a result or table → **Export Data**, which writes to your machine. Treat exported files as production data.
- **Admin connections:** after a master-password rotation the login fails with `password authentication failed`. Run the script with `--role admin --copy-password` and paste the new password when DBeaver asks.

### Using the read-only login

The `readonly` role:

- can `SELECT` from every table and view in the database, including tables created later (`pg_read_all_data`);
- starts every session with `default_transaction_read_only = on`, and has no write privileges, so `INSERT`, `UPDATE`, `DELETE` and DDL are refused;
- is per database: the same user name with a different password in each database, so take the password from that database's secret.

Good practice on a production database:

- **Bound your queries.** Add `LIMIT`, filter on indexed columns, and avoid `SELECT *` on large tables. Set a guard for your session:

  ```sql
  SET statement_timeout = '60s';
  ```

- **Export with `\copy`**, which writes to your machine:

  ```sql
  \copy (SELECT id, created_at FROM public.some_table WHERE created_at > now() - interval '7 days') TO 'export.csv' WITH CSV HEADER
  ```

- **List what is there:**

  ```sql
  \dn                     -- schemas
  \dt <schema>.*          -- tables in a schema
  \d+ <schema>.<table>    -- columns and indexes
  ```

- **Don't keep long idle transactions open.** In an IDE, use auto-commit, or end the transaction, so you don't hold locks or block vacuum.
- **Treat exported data as production data.** Don't paste it into tickets or chat, and delete local exports when you're done.

If you need to change data, ask a database admin. Don't share the master password.

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `No AWS accounts are available to you` | You are not in `aiae-db-readonly` / `aiae-db-admins`, or the assignment is still provisioning. Ask a platform admin. |
| `You must specify a region` | `aws configure set region us-east-1 --profile <profile>` |
| `SessionManagerPlugin is not found` | Install the Session Manager plugin and open a new terminal. |
| `AccessDeniedException` on `start-session` | Your role has no tunnel permission, or you used a different document. Use exactly `AWS-StartPortForwardingSessionToRemoteHost`. |
| `AccessDeniedException` on `get-secret-value` | Read-only users can read only the `db-readonly` secrets, not the master secret. |
| `Connection refused` on `127.0.0.1:15432` | The tunnel isn't running, or is on another port. Restart step 2. |
| `password authentication failed` | Wrong database's password, or a stale master password after rotation. Fetch it again in step 3. |
| `The SSO session has expired` / `ExpiredToken` | Run `aws sso login` or `aws login` again. |

## Local validation

These commands do not call AWS APIs:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
helm lint charts/cluster-bootstrap
```
