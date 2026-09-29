# Non-sensitive outputs for wiring the GitHub environments and AIAE-helm.
# No password, SecretString or private key is ever emitted here.

output "paicing_github_ci_role_arn" {
  description = "Value for the GitHub environment variable AWS_ROLE_TO_ASSUME."
  value       = try(aws_iam_role.paicing_github_ci[0].arn, null)
}

output "paicing_ecr_repository_url" {
  description = "ECR repository holding all four images of a release (application, builder, fetcher, migrations)."
  value       = try(aws_ecr_repository.paicing[0].repository_url, null)
}

output "paicing_application_role_arn" {
  description = "IRSA role ARN for the application Pod's serviceAccount. Reads the application secret only; it has no access to the RDS master credentials."
  value       = try(aws_iam_role.paicing_application[0].arn, null)
}

output "paicing_migrate_role_arn" {
  description = "IRSA role ARN for the migration Job's serviceAccount. The only identity holding the RDS master credentials."
  value       = try(aws_iam_role.paicing_migrate[0].arn, null)
}

output "paicing_secret_name" {
  description = <<-EOT
    The chart's secretsManager.awsSecretName.

    NOT a GitHub environment variable for this application: Pacing has no
    frontend and no build-time configuration, so no workflow reads it. The
    value reaches the Pod through the Secrets Store CSI driver.

    Keys a human must populate (Terraform never writes values):
      DATABASE_URL                  postgres://pacing_app:<password>@<host>:5432/pacing?sslmode=require
                                    The APPLICATION's own role, not the master.
                                    You choose this password; AWS never rotates
                                    it. The migration Job reads the role name and
                                    password back out of this DSN and reconciles
                                    the database role to match, so this string is
                                    the single source for both.
                                    Percent-encode any of @ : / ? # in it.
      POSTGRES_HOST                 used by the migration Job
      POSTGRES_PORT                 used by the migration Job
      POSTGRES_DB                   used by the migration Job
      HUB_ASSERTION_SECRET          shared with the Operational Hub and nothing else
      TOKEN_SECRET
      N8N_WEBHOOK_SECRET            also signs the in-pod calls to builder/fetcher
      SLACK_BOT_TOKEN
      GOOGLE_SERVICE_ACCOUNT_JSON   BigQuery service-account key, one line
      GOOGLE_SHEETS_OAUTH_JSON      Drive + Sheets OAuth credential, one line:
                                    {"client_id","client_secret","refresh_token"}
                                    A USER refresh token, not a service account:
                                    the Pacings folder lives in that Google
                                    account's own Drive, which a service account
                                    cannot own. Without it the per-pacing Source
                                    spreadsheets are never created, never filled,
                                    and access to them is never revoked.
      OPENROUTER_API_KEY
      OPENROUTER_MODEL

    POSTGRES_USER and POSTGRES_PASSWORD are deliberately absent. The master
    credentials are read straight from the RDS-managed secret by the migration
    Job, and the application never uses them at all.
  EOT
  value       = try(aws_secretsmanager_secret.paicing[0].name, null)
}

output "paicing_secret_arn" {
  description = "ARN of the Pacing application secret."
  value       = try(aws_secretsmanager_secret.paicing[0].arn, null)
}

output "paicing_database_endpoint" {
  description = "Value for the secret keys POSTGRES_HOST (host portion) and POSTGRES_PORT."
  value       = try(aws_db_instance.paicing_postgres[0].endpoint, null)
}

output "paicing_database_name" {
  description = "Value for the secret key POSTGRES_DB."
  value       = try(aws_db_instance.paicing_postgres[0].db_name, null)
}

output "paicing_database_username" {
  description = <<-EOT
    Master user name, for reference and break-glass access. Not a key of the
    application secret: the application and the migration Job both read the
    user name and password from the RDS-managed secret below.
  EOT
  value       = try(aws_db_instance.paicing_postgres[0].username, null)
}

output "paicing_database_master_secret_arn" {
  description = <<-EOT
    The RDS-managed secret holding the database credentials, for the chart's
    secretsManager.databaseCredentialsSecret.awsSecretName.

    AWS rotates this password every seven days and that schedule cannot be
    turned off while RDS manages it, which is why nothing may hold a copy —
    including a connection saved in a local SQL client, which will need the
    current value re-read from here roughly weekly.
  EOT
  value       = try(aws_db_instance.paicing_postgres[0].master_user_secret[0].secret_arn, null)
}

output "paicing_database_publicly_accessible" {
  description = "Whether the Pacing database accepts connections from outside the VPC. True only in DEV, scoped to paicing_database_public_access_cidrs."
  value       = try(aws_db_instance.paicing_postgres[0].publicly_accessible, null)
}
