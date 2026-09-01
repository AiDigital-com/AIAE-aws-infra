# Secrets Manager container for the AIAE Onboarding Platform.
#
# Terraform creates the container and never its contents: putting a
# SecretString here would write every value into Terraform state in plain text.
# The required JSON keys are documented in the outputs; a human populates them.
#
# POSTGRES_PASSWORD is copied from the RDS-managed master secret
# (aws_db_instance.onboarding.master_user_secret) — see outputs.

resource "aws_secretsmanager_secret" "onboarding" {
  count = var.enable_onboarding_platform ? 1 : 0

  name        = local.onboarding_secret_name
  description = "AIAE Onboarding Platform ${var.environment} runtime configuration. Populate SecretString manually; Terraform never writes values."

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}
