environment = "prod"

aws_account_id = "125093118532"
aws_region     = "us-east-1"

github_org = "AiDigital-com"
github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-operational-hub@1327019535:environment:prod",
]

create_github_oidc_provider  = true
github_oidc_provider_arn     = ""
create_ecr_repository        = true
create_github_codeconnection = false
github_codeconnection_arn    = ""

# Enable after AWS Identity Center group/user IDs are known and the GitHub
# CodeConnections handshake is AVAILABLE.
enable_argocd             = false
enable_gitops_bootstrap   = false
argocd_idc_instance_arn   = ""
argocd_rbac_role_mappings = {}

enable_secrets_store_csi = true

# DNS is managed in GoDaddy. Keep disabled until manual ACM validation or
# Route53 subdomain delegation is represented in Terraform.
route53_zone_name         = ""
enable_public_certificate = false
enable_external_dns       = false

# Frontend deployment remains disabled until the frontend is ready.
enable_frontend = false

vpc_cidr              = "10.50.0.0/16"
availability_zones    = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs   = ["10.50.0.0/24", "10.50.1.0/24"]
private_subnet_cidrs  = ["10.50.10.0/24", "10.50.11.0/24"]
database_subnet_cidrs = ["10.50.20.0/24", "10.50.21.0/24"]

database_instance_class      = "db.t4g.medium"
database_allocated_storage   = 100
database_multi_az            = true
database_publicly_accessible = false
database_public_access_cidrs = []
enable_deletion_protection   = true
