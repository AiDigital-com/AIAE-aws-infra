environment = "prod"

aws_account_id = "125093118532"
aws_region     = "us-east-1"

eks_cloudwatch_log_retention_days = 1
rds_cloudwatch_log_retention_days = 1
enable_application_logging        = true
application_log_retention_days    = 1

# Production-only metrics stack. DEV keeps the module default (disabled).
enable_observability       = true
prometheus_scrape_interval = "60s"
prometheus_retention_days  = 30
# Managed Grafana uses users from the organization Identity Center instance.
grafana_rbac_role_mappings = {
  platform_admins = {
    role = "ADMIN"
    user_ids = [
      "e4d8b4d8-2011-7065-8ede-acee6afd190d", #gleb.mozhaiskii@aidigital.com
      "9468a498-c0f1-70c2-0935-4e1bd435e417", # azat.nabiev@aidigital.com
    ]
  }
  platform_viewers = {
    role = "VIEWER"
    user_ids = [
      "e4d8b4b8-6031-7058-dd27-9bb11a2b34d5", # beatris.felises@aidigital.com
      "4498a4d8-a0c1-70fb-1236-5886e519a328", # illia.holubiev@aidigital.com
    ]
  }
}

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
enable_gitops_bootstrap = true
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
frontend_domain_name                     = "aiae-operational-hub.aidigital.tech"
frontend_certificate_request_domain_name = "aiae-operational-hub.aidigital.tech"
frontend_api_origin_domain_name          = "k8s-aiaeprod-operatio-b9a42c7365-1060243398.us-east-1.elb.amazonaws.com"

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

# --- AIAE Onboarding Platform (application-scoped) --------------------------
enable_onboarding_platform = true

# Same numeric organization and repository IDs as DEV; only the environment
# claim differs. The organization's custom OIDC subject embeds both IDs, so a
# plain repo:<org>/<repo>:environment:prod subject would never match.
onboarding_github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-onboarding-platform@1303870401:environment:prod",
]

# Pinned minor, not a bare "16". AWS resolves a bare major to its current
# default, which gave 16.13 in DEV — OLDER than the 16.14 source database, and
# pg_restore refuses to load a dump from a newer server.
onboarding_database_engine_version = "16.15"

# Sized like the Operational Hub production database. Storage is larger than
# the 54 MB being migrated because gp3 IOPS scale with allocated size, and
# autoscaling doubles the ceiling.
onboarding_database_instance_class    = "db.t4g.medium"
onboarding_database_allocated_storage = 100
onboarding_database_multi_az          = true

# Never public in production. rds-aiae-onboarding.tf also carries a precondition
# that fails the plan outright if this is ever set to true while environment is
# prod, so the DEV exception cannot be copied here by accident.
onboarding_database_publicly_accessible = false
onboarding_database_public_access_cidrs = []

# Two-step cutover, because DNS lives in GoDaddy.
#
# Step 1 (now): request the certificate only. It stays PENDING_VALIDATION until
# the validation CNAME is added by hand, and CloudFront serves on its generated
# *.cloudfront.net domain meanwhile. Attaching an unissued certificate fails the
# apply with InvalidViewerCertificate, which is exactly what happened when both
# were set at once.
onboarding_frontend_certificate_request_domain_name = "aiae-onboarding.aidigital.tech"

# Step 2 (after the certificate reaches ISSUED): set this to the same hostname
# and apply again. That attaches the alias and the certificate to CloudFront.
# Only then does the GoDaddy traffic record get repointed.
onboarding_frontend_domain_name = ""

# Verification subdomain. Covered by the same certificate and attached as a
# CloudFront alias, so the authenticated surface can be exercised on a real
# aidigital.tech hostname — which the production Clerk instance requires —
# while aiae-onboarding.aidigital.tech still points at the old deployment.
onboarding_frontend_certificate_alternative_names = ["aiae-onboarding-new.aidigital.tech"]

# Empty until Argo CD has created the Ingress and the ALB exists. Fill in and
# re-apply, exactly as was done for DEV.
onboarding_frontend_api_origin_domain_name = "k8s-aiaeprod-aiaeonbo-99333fe377-1861569064.us-east-1.elb.amazonaws.com"
