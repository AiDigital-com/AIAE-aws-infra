environment = "dev"

aws_account_id = "496336474487"
aws_region     = "us-east-1"

eks_cloudwatch_log_retention_days = 1
rds_cloudwatch_log_retention_days = 1

github_org = "AiDigital-com"
github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-operational-hub@1327019535:environment:dev",
]

create_github_oidc_provider  = true
create_ecr_repository        = true
create_github_codeconnection = true

# AWS Identity Center and the GitHub connection are configured for DEV.
enable_argocd           = true
enable_gitops_bootstrap = true
argocd_idc_instance_arn = "arn:aws:sso:::instance/ssoins-7223bd3cc2b2f348"
argocd_rbac_role_mappings = {
  platform_admins = {
    role = "ADMIN"
    identities = [{
      id   = "d408d408-1041-70bd-5c75-f03722987f43"
      type = "SSO_GROUP"
    }]
  }
}

enable_secrets_store_csi = true

# DNS is managed in GoDaddy. Keep disabled until manual ACM validation or
# Route53 subdomain delegation is represented in Terraform.
route53_zone_name               = ""
enable_public_certificate       = false
enable_external_dns             = false
enable_frontend                 = true
frontend_api_origin_domain_name = "k8s-aiaedev-operatio-b401294554-2047536698.us-east-1.elb.amazonaws.com"

vpc_cidr              = "10.40.0.0/16"
availability_zones    = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs   = ["10.40.0.0/24", "10.40.1.0/24"]
private_subnet_cidrs  = ["10.40.10.0/24", "10.40.11.0/24"]
database_subnet_cidrs = ["10.40.20.0/24", "10.40.21.0/24"]

database_instance_class      = "db.t4g.small"
database_allocated_storage   = 50
database_multi_az            = false
database_publicly_accessible = true
database_public_access_cidrs = ["0.0.0.0/0"]
enable_deletion_protection   = false

# --- AIAE Onboarding Platform (application-scoped) --------------------------
enable_onboarding_platform = true

# Numeric organization and repository IDs come from the GitHub API; the
# organization's OIDC subject template embeds them, so a plain
# repo:<org>/<repo>:environment:dev subject would never match.
onboarding_github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-onboarding-platform@1303870401:environment:dev",
]

onboarding_database_instance_class    = "db.t4g.small"
onboarding_database_allocated_storage = 20
onboarding_database_multi_az          = false

# Public by explicit request, so the database can be opened directly from the
# IDE. Scoped to the developer's current address rather than the 0.0.0.0/0 that
# the Operational Hub DEV database uses: the credential is an AWS-generated
# master password, and a world-reachable Postgres port is worth avoiding when a
# single CIDR does the same job.
#
# When your public IP changes, `curl -s https://checkip.amazonaws.com` gives the
# new one; update the CIDR below and re-apply. Widen to ["0.0.0.0/0"] only as a
# deliberate, temporary decision.
#
# The PROD precondition in rds-aiae-onboarding.tf rejects public access outright,
# so this cannot leak into production by copying the file.
onboarding_database_publicly_accessible = true
onboarding_database_public_access_cidrs = ["188.255.211.8/32"]

# Empty on the first apply: the ALB does not exist until Argo CD has created
# the Ingress. Set to the Ingress address and re-apply to attach the /api/*
# and /actuator/* CloudFront behaviours.
onboarding_frontend_api_origin_domain_name = ""
