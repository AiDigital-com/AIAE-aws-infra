# Secrets Manager container for Pacing.
#
# Terraform creates the container and never its contents: putting a
# SecretString here would write every value into Terraform state in plain text.
# The required JSON keys are documented in the outputs; a human populates them.
#
# POSTGRES_USER and POSTGRES_PASSWORD are deliberately NOT keys of this secret.
# AWS owns the database password and rotates it every seven days into the
# RDS-managed secret, and that schedule cannot be turned off while RDS manages
# the password. A hand-copied duplicate here would go stale and fail — which is
# exactly what broke Operational Hub and the Onboarding Platform in September
# 2026. Both the application and the migration Job read those two fields from
# the owning secret instead; see iam-aiae-paicing.tf.

resource "aws_secretsmanager_secret" "paicing" {
  count = var.enable_paicing ? 1 : 0

  name        = local.paicing_secret_name
  description = "Pacing ${var.environment} runtime configuration. Populate SecretString manually; Terraform never writes values."

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}
