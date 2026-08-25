environment = "dev"

aws_account_id = "496336474487"
aws_region     = "us-east-1"

github_org = "AiDigital-com"

create_github_oidc_provider  = true
create_ecr_repository        = true
create_github_codeconnection = false

# Enable after AWS Identity Center IDs and the GitHub connection are available.
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
enable_frontend           = false

vpc_cidr              = "10.40.0.0/16"
availability_zones    = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs   = ["10.40.0.0/24", "10.40.1.0/24"]
private_subnet_cidrs  = ["10.40.10.0/24", "10.40.11.0/24"]
database_subnet_cidrs = ["10.40.20.0/24", "10.40.21.0/24"]

database_instance_class    = "db.t4g.small"
database_allocated_storage = 50
database_multi_az          = false
enable_deletion_protection = false
