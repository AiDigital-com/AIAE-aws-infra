output "github_backend_ci_role_arn" {
  description = "Set this as GitHub variable AWS_BACKEND_CI_ROLE_TO_ASSUME."
  value       = aws_iam_role.github_backend_ci.arn
}

output "github_oidc_provider_arn" {
  description = "Pass this into other environment tfvars as github_oidc_provider_arn."
  value       = local.github_oidc_provider_arn
}

output "aws_region" {
  description = "Set this as GitHub variable AWS_REGION."
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "Backend ECR repository URL."
  value       = local.ecr_repository_url
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "secrets_manager_secret_name" {
  description = "Application Secrets Manager secret to populate."
  value       = aws_secretsmanager_secret.app.name
}

output "application_iam_role_arn" {
  description = "Set this as eks.amazonaws.com/role-arn on the operational-hub-api service account."
  value       = aws_iam_role.application.arn
}

output "rds_master_user_secret_arn" {
  description = "RDS-managed master credential secret. Do not expose its SecretString in Terraform."
  value       = try(aws_db_instance.postgres.master_user_secret[0].secret_arn, null)
}

output "api_certificate_arn" {
  description = "ACM certificate used by the EKS Auto Mode ALB IngressClass."
  value       = try(aws_acm_certificate_validation.api[0].certificate_arn, null)
}

output "argocd_capability_role_arn" {
  description = "IAM capability role used by AWS-managed Argo CD."
  value       = try(aws_iam_role.argocd_capability[0].arn, null)
}

output "argocd_server_url" {
  description = "AWS-managed Argo CD UI URL."
  value       = try(aws_eks_capability.argocd[0].configuration[0].argo_cd[0].server_url, null)
}

output "github_codeconnection_arn" {
  description = "Authorize this connection in the AWS console, then pass it to the other environment."
  value       = local.github_codeconnection_arn == "" ? null : local.github_codeconnection_arn
}

output "gitops_helm_repository_url" {
  description = "Repository URL used by managed Argo CD."
  value       = local.gitops_helm_repository_url == "" ? null : local.gitops_helm_repository_url
}

output "gitops_versions_repository_url" {
  description = "Versions repository URL used by managed Argo CD."
  value       = local.gitops_versions_repository_url == "" ? null : local.gitops_versions_repository_url
}

output "frontend_bucket_name" {
  description = "S3 bucket for frontend artifacts."
  value       = try(aws_s3_bucket.frontend[0].id, null)
}

output "frontend_cloudfront_distribution_id" {
  description = "CloudFront distribution ID used for cache invalidation."
  value       = try(aws_cloudfront_distribution.frontend[0].id, null)
}

output "frontend_url" {
  description = "Frontend URL when the optional S3/CloudFront stack is enabled."
  value = try(
    var.frontend_domain_name == "" ? "https://${aws_cloudfront_distribution.frontend[0].domain_name}" : "https://${var.frontend_domain_name}",
    null,
  )
}
