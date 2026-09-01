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
  description = "Custom hostname for the frontend. DEV intentionally uses the generated CloudFront domain and leaves this empty."
  default     = ""
}
