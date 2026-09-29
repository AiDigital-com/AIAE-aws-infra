# Dedicated PostgreSQL instance for Pacing.
#
# Deliberately NOT a schema on an existing instance: sharing the Kubernetes
# cluster does not imply sharing data ownership, credentials, capacity or
# upgrade lifecycle. Pacing's schema (`access`, 18 tables) is created from
# scratch by the node-pg-migrate PreSync Job; nothing is restored here.

resource "aws_security_group" "paicing_rds" {
  count = var.enable_paicing ? 1 : 0

  name        = "${local.paicing_name}-rds"
  description = "PostgreSQL access for Pacing"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from approved networks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat(
      [var.vpc_cidr],
      var.paicing_database_publicly_accessible ? var.paicing_database_public_access_cidrs : [],
    )
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "paicing_postgres" {
  count = var.enable_paicing ? 1 : 0

  name       = "${local.paicing_name}-postgres"
  subnet_ids = module.vpc.database_subnets
}

# publicly_accessible=true is not sufficient on its own: an instance only
# becomes reachable from the internet when its subnet group routes to an
# internet gateway. Created only while public access is enabled.
resource "aws_db_subnet_group" "paicing_postgres_public" {
  count = var.enable_paicing && var.paicing_database_publicly_accessible ? 1 : 0

  name       = "${local.paicing_name}-postgres-public"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_instance" "paicing_postgres" {
  count = var.enable_paicing ? 1 : 0

  identifier = "${local.paicing_name}-postgres"

  engine         = "postgres"
  engine_version = var.paicing_database_engine_version
  instance_class = var.paicing_database_instance_class

  allocated_storage     = var.paicing_database_allocated_storage
  max_allocated_storage = var.paicing_database_allocated_storage * 2
  storage_encrypted     = true

  db_name  = var.paicing_database_name
  username = var.paicing_database_username

  # AWS generates and rotates the master password into its own managed secret.
  # No password is ever produced as a Terraform value, so none can leak through
  # state, a plan file, or an output.
  manage_master_user_password = true

  db_subnet_group_name = var.paicing_database_publicly_accessible ? (
    aws_db_subnet_group.paicing_postgres_public[0].name
  ) : aws_db_subnet_group.paicing_postgres[0].name
  vpc_security_group_ids = [aws_security_group.paicing_rds[0].id]
  publicly_accessible    = var.paicing_database_publicly_accessible
  multi_az               = var.paicing_database_multi_az
  apply_immediately      = var.environment != "prod"

  backup_retention_period   = var.environment == "prod" ? 14 : 0
  deletion_protection       = var.enable_deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.paicing_name}-postgres-final" : null

  # Matches the platform's current intent: Performance Insights was turned off
  # for the other databases by origin/main commit 9826e10 ("Focus production
  # observability on application and database", 2026-08-30).
  performance_insights_enabled = false

  lifecycle {
    precondition {
      condition     = !var.paicing_database_publicly_accessible || length(var.paicing_database_public_access_cidrs) > 0
      error_message = "paicing_database_public_access_cidrs must contain at least one CIDR when the database is public."
    }

    # The DEV database is public by explicit owner decision so it can be opened
    # from IntelliJ. This precondition is what stops that setting reaching
    # production by someone copying the tfvars block.
    precondition {
      condition     = var.environment != "prod" || !var.paicing_database_publicly_accessible
      error_message = "The PROD Pacing database must never be publicly accessible."
    }

    # 0.0.0.0/0 is what the Operational Hub DEV database uses, by an older
    # decision. A new application does not inherit it: the credential is an
    # AWS-generated master password, and a world-reachable Postgres port buys
    # nothing over a single developer address.
    precondition {
      condition     = !contains(var.paicing_database_public_access_cidrs, "0.0.0.0/0")
      error_message = "paicing_database_public_access_cidrs must not contain 0.0.0.0/0; scope it to the developer's address."
    }
  }
}
