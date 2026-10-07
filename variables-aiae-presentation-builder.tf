# Inputs for the AIAE Presentation Builder application. Every variable defaults
# to the inert value so an environment that has not opted in (currently PROD)
# plans exactly as before this file existed.

variable "enable_presentation_builder" {
  type        = bool
  description = "Create the AIAE Presentation Builder application resources in this environment."
  default     = false
}

variable "presentation_builder_github_oidc_subjects" {
  type        = list(string)
  description = <<-EOT
    Exact GitHub OIDC subjects allowed to assume the Presentation Builder CI role.
    The organization embeds numeric organization and repository IDs, e.g.
    repo:AiDigital-com@184130113/AIAE-presentation-builder@1349389858:environment:dev
    Never widen this to a wildcard repository or branch. The source repository is
    PUBLIC, so a wildcard subject would expose a role that can publish images.
  EOT
  default     = []
}

variable "presentation_builder_database_engine_version" {
  type        = string
  description = <<-EOT
    Exact PostgreSQL minor version. Pinned deliberately rather than left as "16":
    AWS resolves a bare major to whatever minor it currently defaults to, which
    produced 16.13 on the first Operational Hub instance while later ones got
    16.15. This database starts empty — no dump is restored into it — so the
    version carries no restore-compatibility floor, only the pinning rule.
  EOT
  default     = "16.15"
}

variable "presentation_builder_database_instance_class" {
  type        = string
  description = "Instance class for the Presentation Builder database."
  default     = "db.t4g.small"
}

variable "presentation_builder_database_allocated_storage" {
  type        = number
  description = "Allocated storage in GiB for the Presentation Builder database."
  default     = 20
}

variable "presentation_builder_database_name" {
  type        = string
  description = "Initial database name."
  default     = "aipresentationbuilder"
}

variable "presentation_builder_database_username" {
  type        = string
  description = "Master username. The password is generated and held in an RDS-managed secret; it is never placed in Terraform state or outputs."
  default     = "aipresentationbuilder"
}

variable "presentation_builder_database_multi_az" {
  type        = bool
  description = "Run the Presentation Builder database Multi-AZ."
  default     = false
}

# Deliberately NOT wired to the shared database_publicly_accessible /
# database_public_access_cidrs variables. Those carry an explicit, reviewed
# business exception for the Operational Hub DEV database (0.0.0.0/0). A new
# application does not inherit that exception.
variable "presentation_builder_database_publicly_accessible" {
  type        = bool
  description = "Expose the Presentation Builder database publicly. Keep false; PROD must never be true."
  default     = false
}

variable "presentation_builder_database_public_access_cidrs" {
  type        = list(string)
  description = "Source CIDRs permitted to reach the database when presentation_builder_database_publicly_accessible=true. Never 0.0.0.0/0 in PROD."
  default     = []
}

variable "presentation_builder_frontend_api_origin_domain_name" {
  type        = string
  description = <<-EOT
    Hostname of the ALB that CloudFront forwards /api/* and /actuator/* to.
    Empty on the first apply: the ALB does not exist until Argo CD has created
    the Ingress. Fill it in and re-apply once the Ingress reports an address.
  EOT
  default     = ""
}

variable "presentation_builder_frontend_certificate_request_domain_name" {
  type        = string
  description = <<-EOT
    Hostname to REQUEST an ACM certificate for without attaching it to
    CloudFront yet. Splitting request from attachment is what makes the
    two-step external-DNS cutover expressible in configuration: the
    certificate can sit in PENDING_VALIDATION while CloudFront keeps serving
    on its generated domain.

    DEV leaves this empty and uses the generated *.cloudfront.net domain, which
    supplies TLS without any certificate or GoDaddy record. The production
    hostname aiae-presentation-builder.aidigital.tech currently resolves to the
    Replit deployment and must keep doing so until the PROD cutover.
  EOT
  default     = ""
}

variable "presentation_builder_frontend_certificate_alternative_names" {
  type        = list(string)
  description = <<-EOT
    Additional hostnames covered by the same certificate, and eligible for
    attachment through presentation_builder_frontend_attached_aliases.

    Used for a verification subdomain: the production hostname can stay pointed
    at Replit while a second name serves the AWS deployment, so the whole
    authenticated surface is testable before any traffic moves.

    ACM cannot add names to an existing certificate, so changing this list
    replaces the certificate. That is free while it is still
    PENDING_VALIDATION and attached to nothing.
  EOT
  default     = []
}

variable "presentation_builder_frontend_attached_aliases" {
  type        = list(string)
  description = <<-EOT
    Hostnames actually ATTACHED to CloudFront as aliases. Deliberately separate
    from the certificate variables, because being covered by the certificate and
    being served are different decisions taken at different times.

    Every name listed here must be covered by the certificate, or CloudFront
    rejects the distribution. An alias attracts no traffic by itself: it only
    tells CloudFront which Host headers to accept, and DNS decides what arrives.
    Leave empty to serve on the generated CloudFront domain alone, which is what
    DEV does.
  EOT
  default     = []
}
