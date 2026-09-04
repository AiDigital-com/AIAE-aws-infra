# Application-scoped locals for the AIAE Onboarding Platform.
#
# This root contains BOTH the shared AIAE platform (VPC, EKS, Argo CD, GitHub
# OIDC provider, CodeConnections) and the resources of the first application
# that was onboarded, Operational Hub. Its application resources are unkeyed
# singletons (aws_ecr_repository.backend, aws_db_instance.postgres, ...).
#
# A second application therefore adds NEW, separately named resources rather
# than converting those singletons to for_each: re-keying a live address is a
# destroy/create of the RDS instance, the ECR repository and the CloudFront
# distribution. Every address in this file is new, so `terraform plan` must
# report zero destroyed and zero replaced resources.

locals {
  onboarding_name = "aiae-onboarding-${var.environment}"

  onboarding_ecr_repository_name = "aidigital.aiae-projects/onboarding-platform-application"

  onboarding_secret_name = var.environment == "prod" ? "AIAE-PRD/aiae-onboarding" : "AIAE-DEV/aiae-onboarding"

  # The organization customizes the GitHub OIDC subject to embed numeric
  # organization and repository IDs, so a plain
  # repo:<org>/<repo>:environment:<env> subject never matches and the workflow
  # fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  # Supplied explicitly per environment in env/*.tfvars.
  onboarding_github_subjects = var.onboarding_github_oidc_subjects

  # Both the API pod and the Liquibase PreSync Job assume this role: the Job
  # reads the same database credentials from the Secrets Store CSI mount.
  onboarding_service_account_subjects = [
    "system:serviceaccount:${local.app_namespace}:aiae-onboarding-api",
    "system:serviceaccount:${local.app_namespace}:aiae-onboarding-api-liquibase",
  ]

  onboarding_frontend_bucket_name  = "${local.onboarding_name}-frontend-${var.aws_account_id}"
  onboarding_materials_bucket_name = "${local.onboarding_name}-materials-${var.aws_account_id}"
}
