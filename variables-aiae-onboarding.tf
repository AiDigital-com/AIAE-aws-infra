# Inputs for the AIAE Onboarding Platform application. Every variable defaults
# to the inert value so an environment that has not opted in (currently PROD)
# plans exactly as before this file existed.

variable "enable_onboarding_platform" {
  type        = bool
  description = "Create the AIAE Onboarding Platform application resources in this environment."
  default     = false
}

variable "onboarding_github_oidc_subjects" {
  type        = list(string)
  description = <<-EOT
    Exact GitHub OIDC subjects allowed to assume the Onboarding Platform CI role.
    The organization embeds numeric organization and repository IDs, e.g.
    repo:AiDigital-com@184130113/AIAE-onboarding-platform@1303870401:environment:dev
    Never widen this to a wildcard repository or branch.
  EOT
  default     = []
}

variable "onboarding_database_engine_version" {
  type        = string
  description = <<-EOT
    Exact PostgreSQL minor version. Pinned deliberately rather than left as "16":
    AWS resolves a bare major to whatever minor it currently defaults to, which
    produced 16.13 in DEV. A dump taken from a NEWER server cannot be restored
    into an older one, and the source database (Replit/Neon) is 16.14, so the
    target must be 16.14 or later.
  EOT
  default     = "16.15"
}

variable "onboarding_database_instance_class" {
  type        = string
  description = "Instance class for the Onboarding Platform database."
  default     = "db.t4g.small"
}

variable "onboarding_database_allocated_storage" {
  type        = number
  description = "Allocated storage in GiB for the Onboarding Platform database."
  default     = 20
}

variable "onboarding_database_name" {
  type        = string
  description = "Initial database name."
  default     = "aionboarding"
}

variable "onboarding_database_username" {
  type        = string
  description = "Master username. The password is generated and held in an RDS-managed secret; it is never placed in Terraform state or outputs."
  default     = "aionboarding"
}

variable "onboarding_database_multi_az" {
  type        = bool
  description = "Run the Onboarding Platform database Multi-AZ."
  default     = false
}

# Deliberately NOT wired to the existing database_publicly_accessible /
# database_public_access_cidrs variables. Those carry an explicit, reviewed
# business exception for the Operational Hub DEV database (0.0.0.0/0). A new
# application does not inherit that exception; developer access should go
# through an SSM tunnel or bastion unless a public CIDR is separately approved.
variable "onboarding_database_publicly_accessible" {
  type        = bool
  description = "Expose the Onboarding Platform database publicly. Keep false; PROD must never be true."
  default     = false
}

variable "onboarding_database_public_access_cidrs" {
  type        = list(string)
  description = "Source CIDRs permitted to reach the database when onboarding_database_publicly_accessible=true. Never 0.0.0.0/0 in PROD."
  default     = []
}

variable "onboarding_frontend_api_origin_domain_name" {
  type        = string
  description = <<-EOT
    Hostname of the ALB that CloudFront forwards /api/* and /actuator/* to.
    Empty on the first apply: the ALB does not exist until Argo CD has created
    the Ingress. Fill it in and re-apply once the Ingress reports an address.
  EOT
  default     = ""
}

variable "onboarding_frontend_domain_name" {
  type        = string
  description = <<-EOT
    Custom hostname to ATTACH to CloudFront as an alias, with its ACM
    certificate as the viewer certificate. Leave empty until that certificate
    is ISSUED: CloudFront rejects a PENDING_VALIDATION certificate outright
    with InvalidViewerCertificate, which fails the whole apply.

    Set onboarding_frontend_certificate_request_domain_name first to request
    the certificate, add the validation CNAME by hand, wait for ISSUED, then
    set this and apply again. DEV leaves both empty and uses the generated
    CloudFront domain.
  EOT
  default     = ""
}

variable "onboarding_frontend_certificate_alternative_names" {
  type        = list(string)
  description = <<-EOT
    Additional hostnames covered by the same certificate, and attached to
    CloudFront as aliases alongside onboarding_frontend_domain_name.

    Used for a verification subdomain: the production hostname can stay pointed
    at the old deployment while a second name serves the new one, so the whole
    authenticated surface is testable before any traffic moves. An alias only
    tells CloudFront which Host headers to accept — it attracts no traffic on
    its own, because that follows DNS.

    ACM cannot add names to an existing certificate, so changing this list
    replaces the certificate. That is free while it is still
    PENDING_VALIDATION and attached to nothing.
  EOT
  default     = []
}

variable "onboarding_frontend_certificate_request_domain_name" {
  type        = string
  description = <<-EOT
    Hostname to REQUEST an ACM certificate for without attaching it to
    CloudFront yet. Splitting request from attachment is what makes the
    two-step external-DNS cutover expressible in configuration: the
    certificate can sit in PENDING_VALIDATION while CloudFront keeps serving
    on its generated domain.
  EOT
  default     = ""
}
