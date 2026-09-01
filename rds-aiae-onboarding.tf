# Dedicated PostgreSQL instance for the AIAE Onboarding Platform.
#
# Deliberately NOT a schema on the Operational Hub instance: sharing the
# Kubernetes cluster does not imply sharing data ownership, credentials,
# capacity or upgrade lifecycle.

resource "aws_security_group" "onboarding_rds" {
  count = var.enable_onboarding_platform ? 1 : 0

  name        = "${local.onboarding_name}-rds"
  description = "PostgreSQL access for the AIAE Onboarding Platform"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from approved networks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat(
      [var.vpc_cidr],
      var.onboarding_database_publicly_accessible ? var.onboarding_database_public_access_cidrs : [],
    )
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "onboarding_postgres" {
  count = var.enable_onboarding_platform ? 1 : 0

  name       = "${local.onboarding_name}-postgres"
  subnet_ids = module.vpc.database_subnets
}

# publicly_accessible=true is not sufficient on its own: an instance only
# becomes reachable from the internet when its subnet group routes to an
# internet gateway. Created only while public access is enabled.
resource "aws_db_subnet_group" "onboarding_postgres_public" {
  count = var.enable_onboarding_platform && var.onboarding_database_publicly_accessible ? 1 : 0

  name       = "${local.onboarding_name}-postgres-public"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_instance" "onboarding_postgres" {
  count = var.enable_onboarding_platform ? 1 : 0

  identifier = "${local.onboarding_name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.onboarding_database_instance_class

  allocated_storage     = var.onboarding_database_allocated_storage
  max_allocated_storage = var.onboarding_database_allocated_storage * 2
  storage_encrypted     = true

  db_name  = var.onboarding_database_name
  username = var.onboarding_database_username

  # AWS generates and rotates the master password into its own managed secret.
  # No password is ever produced as a Terraform value, so none can leak through
  # state, a plan file, or an output.
  manage_master_user_password = true

  db_subnet_group_name = var.onboarding_database_publicly_accessible ? (
    aws_db_subnet_group.onboarding_postgres_public[0].name
  ) : aws_db_subnet_group.onboarding_postgres[0].name
  vpc_security_group_ids = [aws_security_group.onboarding_rds[0].id]
  publicly_accessible    = var.onboarding_database_publicly_accessible
  multi_az               = var.onboarding_database_multi_az
  apply_immediately      = var.environment != "prod"

  backup_retention_period   = var.environment == "prod" ? 14 : 0
  deletion_protection       = var.enable_deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.onboarding_name}-postgres-final" : null

  # false to match the platform's current intent: origin/main commit 9826e10
  # ("Focus production observability on application and database", 2026-08-30)
  # turned Performance Insights off for aws_db_instance.postgres. Copying the
  # pre-change value here would re-introduce what that commit removed.
  performance_insights_enabled = false

  lifecycle {
    precondition {
      condition     = !var.onboarding_database_publicly_accessible || length(var.onboarding_database_public_access_cidrs) > 0
      error_message = "onboarding_database_public_access_cidrs must contain at least one CIDR when the database is public."
    }

    precondition {
      condition     = var.environment != "prod" || !var.onboarding_database_publicly_accessible
      error_message = "The PROD Onboarding Platform database must never be publicly accessible."
    }
  }
}
