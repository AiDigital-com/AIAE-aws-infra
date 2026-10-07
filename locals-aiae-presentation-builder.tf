# Application-scoped locals for the AIAE Presentation Builder.
#
# Every address in this file and its siblings is NEW. The root already holds
# the shared AIAE platform (VPC, EKS, Argo CD, GitHub OIDC provider,
# CodeConnections) plus three onboarded applications, two of which still carry
# unkeyed singleton addresses from when they were the only tenant. Nothing here
# re-keys or renames an existing address, so `terraform plan` must report zero
# destroyed and zero replaced resources.

locals {
  presentation_builder_name = "aiae-presentation-builder-${var.environment}"

  presentation_builder_ecr_repository_name = "aidigital.aiae-projects/presentation-builder-application"

  presentation_builder_secret_name = var.environment == "prod" ? "AIAE-PRD/aiae-presentation-builder" : "AIAE-DEV/aiae-presentation-builder"

  # The organization customizes the GitHub OIDC subject to embed numeric
  # organization and repository IDs, so a plain
  # repo:<org>/<repo>:environment:<env> subject never matches and the workflow
  # fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  # Supplied explicitly per environment in env/*.tfvars.
  presentation_builder_github_subjects = var.presentation_builder_github_oidc_subjects

  # Both the API pod and the Liquibase PreSync Job assume this role: the Job
  # reads the same database credentials from the Secrets Store CSI mount.
  presentation_builder_service_account_subjects = [
    "system:serviceaccount:${local.app_namespace}:aiae-presentation-builder-api",
    "system:serviceaccount:${local.app_namespace}:aiae-presentation-builder-api-liquibase",
  ]

  presentation_builder_frontend_bucket_name = "${local.presentation_builder_name}-frontend-${var.aws_account_id}"
}
