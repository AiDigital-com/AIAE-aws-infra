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
create_github_codeconnection = true
github_codeconnection_arn    = ""

# Enable after AWS Identity Center group/user IDs are known and the GitHub
# CodeConnections handshake is AVAILABLE.
enable_argocd           = true
enable_gitops_bootstrap = false
argocd_idc_instance_arn = "arn:aws:sso:::instance/ssoins-7223b53871c5ac5f"
argocd_rbac_role_mappings = {
  platform_admins = {
    role = "ADMIN"
    identities = [
      {
        id   = "4428e438-a0d1-70a5-566a-3f10d7aa043d"
        type = "SSO_GROUP"
      },
    ]
  }
}

enable_secrets_store_csi = true

# DNS is managed in GoDaddy. Request the CloudFront certificate now, attach
# the hostname only after the manual validation CNAME is active.
route53_zone_name                        = ""
enable_public_certificate                = false
enable_external_dns                      = false
domain_name                              = ""
enable_frontend                          = true
frontend_domain_name                     = ""
frontend_certificate_request_domain_name = "aiae-operational-hub.aidigital.tech"
frontend_api_origin_domain_name          = ""

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
