variable "project" {
  type        = string
  description = "Short project name used in AWS resource names."
  default     = "aiae-operational-hub"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags applied to every AWS resource managed by this stack."
  default     = {}
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_account_id" {
  type        = string
  description = "AWS account id."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account id."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for public/private/database subnets."
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs for EKS workloads."
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "Isolated/private database subnet CIDRs."
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.33"
}

variable "eks_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint. Restrict this before production go-live."
  default     = ["0.0.0.0/0"]
}

variable "eks_cloudwatch_log_retention_days" {
  type        = number
  description = "Retention period for EKS control-plane logs."
  default     = 30
}

variable "enable_application_logging" {
  type        = bool
  description = "Ship application container stdout from the workload namespace to CloudWatch Logs."
  default     = false
}

variable "application_log_retention_days" {
  type        = number
  description = "Retention period for application container logs shipped to CloudWatch Logs."
  default     = 1

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
      1096, 1827, 2192, 2557, 2922, 3288, 3653,
    ], var.application_log_retention_days)
    error_message = "application_log_retention_days must be a CloudWatch Logs supported retention value."
  }
}

variable "github_org" {
  type        = string
  description = "GitHub owner or org that hosts the application and GitOps repositories."

  validation {
    condition     = trimspace(var.github_org) != "" && !startswith(var.github_org, "CHANGE_ME")
    error_message = "github_org must be set to the real GitHub owner before planning."
  }
}

variable "github_app_repo" {
  type        = string
  description = "Application repository name."
  default     = "AIAE-operational-hub"
}

variable "github_oidc_subjects" {
  type        = list(string)
  description = "Explicit GitHub OIDC subject claims. Use this when the organization customizes its OIDC subject template."
  default     = []

  validation {
    condition = alltrue([
      for subject in var.github_oidc_subjects : startswith(subject, "repo:")
    ])
    error_message = "Every github_oidc_subjects entry must start with repo:."
  }
}

variable "github_gitops_versions_repo" {
  type        = string
  description = "GitOps versions repository name."
  default     = "AIAE-helm-versions"
}

variable "github_gitops_helm_repo" {
  type        = string
  description = "GitOps Helm chart repository name."
  default     = "AIAE-helm"
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Create the GitHub OIDC provider in the target AWS account. Set true once in each account."
  default     = false
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "Existing GitHub OIDC provider ARN when create_github_oidc_provider=false."
  default     = ""
}

variable "create_ecr_repository" {
  type        = bool
  description = "Create the shared backend ECR repository in this state. Set true once per AWS account/region."
  default     = false
}

variable "dev_snapshot_image_pair_retention" {
  type        = number
  description = "Number of immutable DEV application and Liquibase snapshot pairs retained in ECR."
  default     = 30

  validation {
    condition     = var.dev_snapshot_image_pair_retention >= 1
    error_message = "dev_snapshot_image_pair_retention must be at least 1."
  }
}

variable "create_github_codeconnection" {
  type        = bool
  description = "Create the shared GitHub CodeConnections connection. It must be authorized once in the AWS console."
  default     = false
}

variable "github_codeconnection_arn" {
  type        = string
  description = "Existing GitHub CodeConnections ARN when create_github_codeconnection=false."
  default     = ""
}

variable "enable_argocd" {
  type        = bool
  description = "Enable the AWS-managed Argo CD EKS capability."
  default     = false
}

variable "argocd_idc_instance_arn" {
  type        = string
  description = "AWS IAM Identity Center instance ARN used by the Argo CD capability."
  default     = ""
}

variable "argocd_idc_region" {
  type        = string
  description = "AWS IAM Identity Center region. Defaults to aws_region when empty."
  default     = ""
}

variable "argocd_rbac_role_mappings" {
  type = map(object({
    role = string
    identities = list(object({
      id   = string
      type = string
    }))
  }))
  description = "Identity Center users/groups mapped to Argo CD ADMIN, EDITOR, or VIEWER roles."
  default     = {}

  validation {
    condition = alltrue(flatten([
      for mapping in values(var.argocd_rbac_role_mappings) : [
        contains(["ADMIN", "EDITOR", "VIEWER"], mapping.role),
        alltrue([for identity in mapping.identities : contains(["SSO_USER", "SSO_GROUP"], identity.type)]),
      ]
    ]))
    error_message = "Argo CD roles must be ADMIN, EDITOR, or VIEWER and identity types must be SSO_USER or SSO_GROUP."
  }
}

variable "enable_gitops_bootstrap" {
  type        = bool
  description = "Create the Argo CD AppProject and Application after the capability is active."
  default     = false
}

variable "gitops_helm_repository_url" {
  type        = string
  description = "Explicit Helm Git repository URL. Leave empty to derive a CodeConnections URL."
  default     = ""
}

variable "gitops_versions_repository_url" {
  type        = string
  description = "Explicit environment versions repository URL. Leave empty to derive a CodeConnections URL."
  default     = ""
}

variable "enable_secrets_store_csi" {
  type        = bool
  description = "Install the AWS Secrets Store CSI provider and enable Kubernetes Secret synchronization."
  default     = true
}

variable "enable_external_dns" {
  type        = bool
  description = "Install ExternalDNS for Route53 records generated from Kubernetes Ingress resources."
  default     = false
}

variable "route53_zone_name" {
  type        = string
  description = "Public Route53 hosted zone name, for example aidigital.tech. Empty disables Route53-managed resources."
  default     = ""
}

variable "enable_public_certificate" {
  type        = bool
  description = "Create and DNS-validate an ACM certificate for domain_name."
  default     = false
}

variable "enable_frontend" {
  type        = bool
  description = "Create the private S3 frontend bucket and CloudFront distribution."
  default     = false
}

variable "frontend_bucket_name" {
  type        = string
  description = "Optional globally unique frontend bucket name."
  default     = null
  nullable    = true
}

variable "frontend_domain_name" {
  type        = string
  description = "Optional custom frontend hostname. Empty uses the generated CloudFront hostname."
  default     = ""
}

variable "frontend_certificate_request_domain_name" {
  type        = string
  description = "Optional hostname for an ACM certificate request before a manually managed DNS name is attached to CloudFront."
  default     = ""
}

variable "frontend_api_origin_domain_name" {
  type        = string
  description = "Optional public ALB hostname used as the CloudFront API origin. Empty disables API proxy behaviors."
  default     = ""
}

variable "database_name" {
  type        = string
  description = "PostgreSQL database name."
  default     = "operational_hub"
}

variable "database_username" {
  type        = string
  description = "PostgreSQL master username. Password is generated by RDS and managed in AWS, not Terraform output."
  default     = "operational_hub"
}

variable "database_instance_class" {
  type        = string
  description = "RDS instance class."
  default     = "db.t4g.small"
}

variable "database_allocated_storage" {
  type        = number
  description = "RDS allocated storage in GiB."
  default     = 50
}

variable "database_multi_az" {
  type        = bool
  description = "Whether RDS should run Multi-AZ."
  default     = false
}

variable "database_publicly_accessible" {
  type        = bool
  description = "Whether RDS receives a public endpoint. Keep false for production."
  default     = false
}

variable "database_public_access_cidrs" {
  type        = list(string)
  description = "External CIDRs allowed to reach a publicly accessible RDS instance."
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.database_public_access_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "Every database_public_access_cidrs value must be a valid CIDR."
  }
}

variable "domain_name" {
  type        = string
  description = "Public application domain for prod. Dev should use a separate host."
  default     = "aiae-operational-hub.aidigital.tech"
}

variable "rds_cloudwatch_log_retention_days" {
  type        = number
  description = "Retention period for PostgreSQL and upgrade logs exported by RDS."
  default     = 30
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection for persistent resources."
  default     = true
}
