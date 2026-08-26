locals {
  name                = "${var.project}-${var.environment}"
  app_namespace       = "aiae-${var.environment}"
  argocd_project_name = "aiae-${var.environment}"

  ecr_repository_name = "aidigital.aiae-projects/operational-hub-application"
  secret_name         = var.environment == "prod" ? "AIAE-PRD/operational-hub" : "AIAE-DEV/operational-hub"

  github_subjects = length(var.github_oidc_subjects) > 0 ? var.github_oidc_subjects : tolist([
    "repo:${var.github_org}/${var.github_app_repo}:environment:${var.environment}",
  ])

  application_service_account_subjects = [
    "system:serviceaccount:${local.app_namespace}:operational-hub-api",
    "system:serviceaccount:${local.app_namespace}:operational-hub-api-liquibase",
  ]

  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn

  ecr_repository_arn = var.create_ecr_repository ? aws_ecr_repository.backend[0].arn : data.aws_ecr_repository.backend[0].arn
  ecr_repository_url = var.create_ecr_repository ? aws_ecr_repository.backend[0].repository_url : data.aws_ecr_repository.backend[0].repository_url

  github_codeconnection_arn = var.create_github_codeconnection ? aws_codeconnections_connection.github[0].arn : var.github_codeconnection_arn
  github_codeconnection_id  = local.github_codeconnection_arn == "" ? "" : element(reverse(split("/", local.github_codeconnection_arn)), 0)

  codeconnection_repository_base_url = local.github_codeconnection_arn == "" ? "" : format(
    "https://codeconnections.%s.amazonaws.com/git-http/%s/%s/%s/%s",
    var.aws_region,
    var.aws_account_id,
    var.aws_region,
    local.github_codeconnection_id,
    var.github_org,
  )

  gitops_helm_repository_url = var.gitops_helm_repository_url != "" ? var.gitops_helm_repository_url : (
    local.codeconnection_repository_base_url == "" ? "" : "${local.codeconnection_repository_base_url}/${var.github_gitops_helm_repo}.git"
  )
  gitops_versions_repository_url = var.gitops_versions_repository_url != "" ? var.gitops_versions_repository_url : (
    local.codeconnection_repository_base_url == "" ? "" : "${local.codeconnection_repository_base_url}/${var.github_gitops_versions_repo}.git"
  )

  route53_enabled = var.route53_zone_name != "" && (
    var.enable_public_certificate ||
    var.enable_external_dns ||
    (var.enable_frontend && local.frontend_certificate_domain_name != "")
  )

  frontend_certificate_domain_name = var.frontend_domain_name != "" ? var.frontend_domain_name : var.frontend_certificate_request_domain_name

  frontend_bucket_name = coalesce(
    var.frontend_bucket_name,
    "${var.project}-${var.environment}-frontend-${var.aws_account_id}",
  )

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.additional_tags)
}
