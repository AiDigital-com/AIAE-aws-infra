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
onboarding_frontend_api_origin_domain_name = "k8s-aiaedev-aiaeonbo-356e22546b-41930847.us-east-1.elb.amazonaws.com"

# --- Pacing (application-scoped) --------------------------------------------
enable_paicing = true

# Numeric organization and repository IDs come from the GitHub API; the
# organization's OIDC subject template embeds them, so a plain
# repo:<org>/<repo>:environment:dev subject would never match.
paicing_github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-paicing@1354553508:environment:dev",
]

paicing_database_instance_class    = "db.t4g.small"
paicing_database_allocated_storage = 20
paicing_database_multi_az          = false

# Public by explicit owner decision (2026-09-18) so the database can be opened
# from IntelliJ. Scoped to the developer's current address, NOT the 0.0.0.0/0
# the Operational Hub DEV database uses — a precondition in
# rds-aiae-paicing.tf rejects that value outright.
#
# When your public IP changes, `curl -s https://checkip.amazonaws.com` gives
# the new one; update the CIDR below and re-apply.
#
# A second precondition rejects public access whenever environment == "prod",
# so this cannot leak into production by copying this block.
paicing_database_publicly_accessible = true
paicing_database_public_access_cidrs = ["188.255.211.8/32"]

# Pacing's three containers share one ReadWriteOnce volume at /dashboards, so
# the cluster needs a StorageClass that actually works. The pre-existing `gp2`
# names a provisioner Kubernetes removed in 1.27 and can never bind.
enable_ebs_storage_class = true

# --- AIAE Presentation Builder (application-scoped) --------------------------
enable_presentation_builder = true

# Numeric organization and repository IDs come from the GitHub API; the
# organization's OIDC subject template embeds them, so a plain
# repo:<org>/<repo>:environment:dev subject would never match. The repository is
# PUBLIC, so this list must stay exact — never a wildcard.
presentation_builder_github_oidc_subjects = [
  "repo:AiDigital-com@184130113/AIAE-presentation-builder@1349389858:environment:dev",
]

# db.t3.small, NOT the db.t4g.small the other three DEV databases run.
#
# READ THIS BEFORE "FIXING" IT BACK. On 2026-10-07 AWS would not create a
# db.t4g.small here at all:
#
#   InvalidVPCNetworkStateFault: You can't create a db.t4g.small database
#   instance because no subnets exist in Availability Zones with sufficient
#   capacity ... choose from these Availability Zones: us-east-1f
#
# RDS places an instance in one of the Availability Zones its DB subnet group
# covers. Both subnet groups here cover us-east-1a and us-east-1b only, because
# that is where this VPC has subnets. AWS offers db.t4g.small for PostgreSQL in
# us-east-1f alone — checked across nine minor versions from 16.4 to 17.6. The
# two sets do not intersect, so there is nowhere to place the instance.
#
# The other three databases are db.t4g.small because they were created on
# 2026-08-27, 2026-08-28 and 2026-09-18, while us-east-1a still offered it.
# Their configuration is not different from this one; only the date is.
#
# db.t3.small is the same size (2 vCPU, 2 GiB) and the same burstable family,
# on Intel rather than Graviton, and AWS offers it in us-east-1a and
# us-east-1b. It costs $0.036/hour against $0.032, so about $3 a month more.
# The architecture is invisible to the application: RDS is managed and the
# backend reaches it over JDBC.
#
# To go back to db.t4g.small, first confirm AWS offers it in one of this VPC's
# Availability Zones:
#
#   aws rds describe-orderable-db-instance-options --engine postgres \
#     --db-instance-class db.t4g.small \
#     --query 'OrderableDBInstanceOptions[].AvailabilityZones[].Name' \
#     --output text | tr '\t' '\n' | sort -u
#
# If us-east-1a or us-east-1b appears, changing this value is a reboot, not a
# replacement. If only us-east-1f appears, the apply will fail exactly as above.
presentation_builder_database_instance_class    = "db.t3.small"
presentation_builder_database_allocated_storage = 20
presentation_builder_database_multi_az          = false

# Public by explicit owner decision (2026-10-07) so the database can be opened
# from the IDE, matching what the Onboarding Platform and Pacing already do.
# Scoped to the developer's current address, NOT the 0.0.0.0/0 the Operational
# Hub DEV database uses — a precondition in rds-aiae-presentation-builder.tf
# rejects that value outright.
#
# When your public IP changes, `curl -s https://checkip.amazonaws.com` gives
# the new one; update the CIDR below and re-apply.
#
# A second precondition rejects public access whenever environment == "prod",
# so this cannot leak into production by copying this block.
presentation_builder_database_publicly_accessible = true
presentation_builder_database_public_access_cidrs = ["188.255.211.8/32"]

# Empty on the first apply: the ALB does not exist until Argo CD has created
# the Ingress. Set it to the Ingress address and re-apply to attach the /api/*
# and /actuator/* CloudFront behaviours.
presentation_builder_frontend_api_origin_domain_name = ""
