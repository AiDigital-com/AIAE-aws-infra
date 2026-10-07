# Secrets Manager container for the AIAE Presentation Builder.
#
# Terraform creates the container and never its contents: putting a
# SecretString here would write every value into Terraform state in plain text.
# The required JSON keys are listed in the outputs; a human populates them.
#
# Database credentials are deliberately NOT among those keys. They live in the
# RDS-managed master user secret, which AWS owns and rotates every seven days,
# and both the application and the Liquibase Job read them from there.

resource "aws_secretsmanager_secret" "presentation_builder" {
  count = var.enable_presentation_builder ? 1 : 0

  name        = local.presentation_builder_secret_name
  description = "AIAE Presentation Builder ${var.environment} runtime configuration. Populate SecretString manually; Terraform never writes values."

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}
