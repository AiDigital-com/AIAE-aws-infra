# Inputs for Pacing. Every variable defaults to the inert value so an
# environment that has not opted in plans exactly as before this file existed.

variable "enable_paicing" {
  type        = bool
  description = "Create the Pacing application resources in this environment."
  default     = false
}

variable "paicing_github_oidc_subjects" {
  type        = list(string)
  description = <<-EOT
    Exact GitHub OIDC subjects allowed to assume the Pacing CI role. The
    organization embeds numeric organization and repository IDs, e.g.
    repo:AiDigital-com@184130113/AIAE-paicing@1354553508:environment:dev
    Never widen this to a wildcard repository or branch.
  EOT
  default     = []
}

variable "paicing_snapshot_image_set_retention" {
  type        = number
  description = <<-EOT
    How many DEV snapshot RELEASES to keep. A Pacing release is FOUR images —
    application, pacing-builder, bq-fetcher and migrations — so the lifecycle
    policy multiplies this by four. Expiring them independently would leave a
    deployment that cannot migrate, or an application whose builder is gone.
  EOT
  default     = 10
}

# ─── Database ────────────────────────────────────────────────────────────────

variable "paicing_database_engine_version" {
  type        = string
  description = <<-EOT
    Exact PostgreSQL minor version, pinned rather than left as a bare major:
    AWS resolves a bare major to whatever minor it currently defaults to, which
    makes the version drift between applies. Pacing starts from an empty
    database created by node-pg-migrate, so there is no dump-compatibility
    floor to respect — only the schema in dash-gate/migrations.
  EOT
  default     = "16.15"
}

variable "paicing_database_instance_class" {
  type        = string
  description = "Instance class for the Pacing database."
  default     = "db.t4g.small"
}

variable "paicing_database_allocated_storage" {
  type        = number
  description = "Allocated storage in GiB for the Pacing database."
  default     = 20
}

variable "paicing_database_name" {
  type        = string
  description = "Initial database name. The application's tables live in the `access` schema, which node-pg-migrate creates inside it."
  default     = "pacing"
}

variable "paicing_database_username" {
  type        = string
  description = "Master username. The password is generated and rotated by AWS in an RDS-managed secret; it is never placed in Terraform state or outputs."
  default     = "pacing"
}

variable "paicing_database_multi_az" {
  type        = bool
  description = "Run the Pacing database Multi-AZ."
  default     = false
}

# Deliberately NOT wired to the shared database_publicly_accessible /
# database_public_access_cidrs variables: those carry the Operational Hub DEV
# exception (0.0.0.0/0), and no new application inherits it.
variable "paicing_database_publicly_accessible" {
  type        = bool
  description = "Expose the Pacing database publicly. DEV only, scoped to named CIDRs; the PROD precondition rejects true outright."
  default     = false
}

variable "paicing_database_public_access_cidrs" {
  type        = list(string)
  description = <<-EOT
    Source CIDRs permitted to reach the database when
    paicing_database_publicly_accessible=true. Keep this to the individual
    developer address; `curl -s https://checkip.amazonaws.com` prints the
    current one. Never 0.0.0.0/0.
  EOT
  default     = []
}

# ─── Shared cluster storage ──────────────────────────────────────────────────

variable "enable_ebs_storage_class" {
  type        = bool
  description = <<-EOT
    Create the cluster's `ebs-gp3` StorageClass.

    This is a SHARED-PLATFORM object, not a Pacing one, which is why it lives in
    the cluster-bootstrap chart rather than in an application chart: an
    application whose Argo Application has prune enabled must not be able to
    delete a cluster-scoped resource other applications may come to depend on.

    The cluster has no usable StorageClass today. The only one present, `gp2`,
    names the in-tree provisioner `kubernetes.io/aws-ebs`, which Kubernetes
    removed in 1.27; this cluster runs 1.33, so it can never bind a volume. The
    working driver is `ebs.csi.eks.amazonaws.com`, built into EKS Auto Mode
    (cluster storageConfig.blockStorage.enabled = true).

    Defaults to false so enabling it is a deliberate, per-environment decision
    and PROD's plan does not change until Pacing is released there.
  EOT
  default     = false
}
