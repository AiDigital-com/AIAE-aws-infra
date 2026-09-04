# Non-sensitive outputs for wiring GitHub environments and AIAE-helm.
# No password, SecretString or private key is ever emitted here.

output "onboarding_github_ci_role_arn" {
  description = "Value for the GitHub environment variable AWS_ROLE_TO_ASSUME."
  value       = try(aws_iam_role.onboarding_github_ci[0].arn, null)
}

output "onboarding_ecr_repository_url" {
  description = "ECR repository for both the application and Liquibase images."
  value       = try(aws_ecr_repository.onboarding[0].repository_url, null)
}

output "onboarding_application_role_arn" {
  description = "IRSA role ARN for the AIAE-helm serviceAccount annotation."
  value       = try(aws_iam_role.onboarding_application[0].arn, null)
}

output "onboarding_secret_name" {
  description = "Value for the GitHub environment variable APP_CONFIG_SECRET_NAME and the chart's secretsManager.awsSecretName."
  value       = try(aws_secretsmanager_secret.onboarding[0].name, null)
}

output "onboarding_frontend_bucket" {
  description = "Value for the GitHub environment variable FRONTEND_BUCKET."
  value       = try(aws_s3_bucket.onboarding_frontend[0].bucket, null)
}

output "onboarding_frontend_distribution_id" {
  description = "Value for the GitHub environment variable FRONTEND_DISTRIBUTION_ID."
  value       = try(aws_cloudfront_distribution.onboarding_frontend[0].id, null)
}

output "onboarding_frontend_url" {
  description = "Public entry point for the application. In DEV this generated domain is the product URL and must appear in AUTH_AUTHORIZED_PARTIES, CORS and CSP."
  value       = try("https://${aws_cloudfront_distribution.onboarding_frontend[0].domain_name}", null)
}

output "onboarding_materials_bucket" {
  description = "Value for the runtime configuration key BUCKET."
  value       = try(aws_s3_bucket.onboarding_materials[0].bucket, null)
}

output "onboarding_database_endpoint" {
  description = "Value for the secret key POSTGRES_HOST (host portion) and POSTGRES_PORT."
  value       = try(aws_db_instance.onboarding_postgres[0].endpoint, null)
}

output "onboarding_database_name" {
  description = "Value for the secret key POSTGRES_DB."
  value       = try(aws_db_instance.onboarding_postgres[0].db_name, null)
}

output "onboarding_database_username" {
  description = <<-EOT
    Master user name, for reference and break-glass access. Not a key of the
    application secret: the application and the Liquibase Job both read the
    user name, along with the password, from the RDS-managed secret below.
  EOT
  value       = try(aws_db_instance.onboarding_postgres[0].username, null)
}

output "onboarding_database_master_secret_arn" {
  description = <<-EOT
    ARN of the RDS-managed secret holding the generated master credentials.
    Set it as services.aiaeOnboardingApi.databaseCredentialsSecretArn in the
    AIAE-helm environment branch. Do NOT copy the password anywhere: AWS
    rotates it every seven days and no copy would follow the rotation, which
    is exactly how this application and Operational Hub both lost their
    database connection in September 2026. The chart points the application
    and the migration Job at this secret so AWS remains its only owner. The
    value itself is never exposed by Terraform.
  EOT
  value       = try(aws_db_instance.onboarding_postgres[0].master_user_secret[0].secret_arn, null)
}

output "onboarding_required_secret_keys" {
  description = <<-EOT
    Exact JSON keys the application secret must contain before the first
    deployment. Database credentials are absent on purpose: they belong to the
    RDS-managed secret, which AWS owns and rotates, and are read from there at
    connection time.
  EOT
  value = [
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "CLERK_PUBLISHABLE_KEY",
    "OPENAI_API_KEY",
  ]
}
