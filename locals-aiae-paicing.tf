# Application-scoped locals for Pacing (AiDigital-com/AIAE-paicing).
#
# Third application in this root, after Operational Hub (unkeyed singletons)
# and the Onboarding Platform. Follows the Onboarding pattern exactly: every
# address here is NEW and flag-gated, so `terraform plan` must report zero
# destroyed and zero replaced resources. Nothing existing is renamed or
# re-keyed — re-keying a live address is a destroy/create of the RDS instance
# and the ECR repository.

locals {
  paicing_name = "aiae-paicing-${var.environment}"

  paicing_ecr_repository_name = "aidigital.aiae-projects/paicing-application"

  paicing_secret_name = var.environment == "prod" ? "AIAE-PRD/aiae-paicing" : "AIAE-DEV/aiae-paicing"

  # The organization customizes the GitHub OIDC subject to embed numeric
  # organization and repository IDs, so a plain
  # repo:<org>/<repo>:environment:<env> subject never matches and the workflow
  # fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  # Supplied explicitly per environment in env/*.tfvars.
  paicing_github_subjects = var.paicing_github_oidc_subjects

  # Pacing runs dash-gate, pacing-builder and bq-fetcher as three containers of
  # ONE Pod — they share a ReadWriteOnce volume at /dashboards, which only one
  # node can mount — so all three run under the Pod's single service account.
  #
  # The migration Job has a SEPARATE service account and a SEPARATE IAM role,
  # not because it is a separate Pod, but because it is the only thing that
  # needs the RDS master credentials. The application logs in as its own
  # least-privilege role (see dash-gate/tools/ensure-app-role.mjs), so giving
  # its pod read access to the master secret would hand a row-level identity
  # the keys to alter the schema.
  paicing_application_service_account_subjects = [
    "system:serviceaccount:${local.app_namespace}:aiae-paicing-api",
  ]

  paicing_migrate_service_account_subjects = [
    "system:serviceaccount:${local.app_namespace}:aiae-paicing-api-migrate",
  ]
}
