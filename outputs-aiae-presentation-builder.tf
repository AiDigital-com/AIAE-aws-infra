# Non-sensitive outputs for wiring GitHub environments and AIAE-helm.
# No password, SecretString or private key is ever emitted here.

output "presentation_builder_github_ci_role_arn" {
  description = "Value for the GitHub environment variable AWS_ROLE_TO_ASSUME."
  value       = try(aws_iam_role.presentation_builder_github_ci[0].arn, null)
}

output "presentation_builder_ecr_repository_url" {
  description = "ECR repository for both the application and Liquibase images."
  value       = try(aws_ecr_repository.presentation_builder[0].repository_url, null)
}

output "presentation_builder_application_role_arn" {
  description = "IRSA role ARN for the AIAE-helm serviceAccount annotation."
  value       = try(aws_iam_role.presentation_builder_application[0].arn, null)
}

output "presentation_builder_secret_name" {
  description = "Value for the GitHub environment variable APP_CONFIG_SECRET_NAME and the chart's secretsManager.awsSecretName."
  value       = try(aws_secretsmanager_secret.presentation_builder[0].name, null)
}

output "presentation_builder_frontend_bucket" {
  description = "Value for the GitHub environment variable FRONTEND_BUCKET."
  value       = try(aws_s3_bucket.presentation_builder_frontend[0].bucket, null)
}

output "presentation_builder_frontend_distribution_id" {
  description = "Value for the GitHub environment variable FRONTEND_DISTRIBUTION_ID."
  value       = try(aws_cloudfront_distribution.presentation_builder_frontend[0].id, null)
}

output "presentation_builder_frontend_url" {
  description = <<-EOT
    Public entry point for the application. In DEV this generated domain is the
    product URL and must appear in AUTH_AUTHORIZED_PARTIES,
    APP_SECURITY_CORS_ALLOWED_ORIGINS and APP_SECURITY_CSP_FRAME_ANCESTORS, and
    be added to the Clerk DEV instance's allowed origins.
  EOT
  value       = try("https://${aws_cloudfront_distribution.presentation_builder_frontend[0].domain_name}", null)
}

output "presentation_builder_database_endpoint" {
  description = "Value for the secret keys POSTGRES_HOST (host portion) and POSTGRES_PORT."
  value       = try(aws_db_instance.presentation_builder_postgres[0].endpoint, null)
}

output "presentation_builder_database_name" {
  description = "Value for the secret key POSTGRES_DB."
  value       = try(aws_db_instance.presentation_builder_postgres[0].db_name, null)
}

output "presentation_builder_database_username" {
  description = <<-EOT
    Master user name, for reference and break-glass access. Not a key of the
    application secret: the application and the Liquibase Job both read the
    user name, along with the password, from the RDS-managed secret below.
  EOT
  value       = try(aws_db_instance.presentation_builder_postgres[0].username, null)
}

output "presentation_builder_database_master_secret_arn" {
  description = <<-EOT
    ARN of the RDS-managed secret holding the generated master credentials.
    Set it as services.presentationBuilderApi.databaseCredentialsSecretArn in
    the AIAE-helm environment branch. Do NOT copy the password anywhere: AWS
    rotates it every seven days and no copy would follow the rotation, which is
    exactly how Operational Hub and the Onboarding Platform both lost their
    database connection in September 2026. The chart points the application and
    the migration Job at this secret so AWS remains its only owner. The value
    itself is never exposed by Terraform.
  EOT
  value       = try(aws_db_instance.presentation_builder_postgres[0].master_user_secret[0].secret_arn, null)
}

output "presentation_builder_required_secret_keys" {
  description = <<-EOT
    Exact JSON keys the application secret must contain before the first
    deployment. Database credentials are absent on purpose: they belong to the
    RDS-managed secret, which AWS owns and rotates, and are read from there at
    connection time.

    GOOGLE_SERVICE_ACCOUNT_JSON is the one that cannot be left out. It is a
    multiline JSON document stored as a single string value, and
    GoogleCredentialsFactory is conditional on it; every Real* Slides and
    Sheets provider is in turn @ConditionalOnBean of that factory, so a blank
    value silently leaves the application on stub providers that generate
    nothing.

    CLERK_SECRET_KEY is degrading rather than fatal. ClerkOAuthTokenService is
    conditional on it and supplies the signed-in user's Google OAuth token, but
    its five consumers all guard with `clerk == null ? null : ...`. Without it
    the application still starts and still generates decks — using the service
    account alone, so decks are not created in the caller's own Drive and
    source spreadsheets cannot be read with the caller's Google account.
  EOT
  value = [
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "CLERK_PUBLISHABLE_KEY",
    "CLERK_SECRET_KEY",
    "ANTHROPIC_API_KEY",
    "GOOGLE_SERVICE_ACCOUNT_JSON",
  ]
}
