# Human access to the private RDS instances.
#
# The databases stay private. People reach them through an SSM Session Manager
# port-forwarding tunnel to a small jump instance in a private subnet:
#
#   laptop:15432 --(Session Manager, IAM-authenticated)--> jump --> <db>:5432
#
# The jump instance has NO inbound rules, no SSH key and no public IP. Who may
# open a tunnel, and which credentials they may read, is decided entirely by
# two customer-managed IAM policies, which Identity Center permission sets
# reference by name:
#
#   <name>-database-admin-access     tunnel + RDS-managed master secrets
#   <name>-database-readonly-access  tunnel + "<app>/db-readonly" secrets only
#
# Only the AWS-StartPortForwardingSessionToRemoteHost document is allowed, so
# the tunnel never becomes a shell on the instance. Session Manager cannot
# restrict the remote host a port-forward targets, so the jump instance's
# security group egress is what limits tunnels to PostgreSQL inside the VPC.

locals {
  database_access_candidates = {
    "operational-hub" = {
      enabled           = true
      address           = aws_db_instance.postgres.address
      master_secret_arn = try(aws_db_instance.postgres.master_user_secret[0].secret_arn, null)
      secret_prefix     = local.secret_name
    }
    "onboarding" = {
      enabled           = var.enable_onboarding_platform
      address           = try(aws_db_instance.onboarding_postgres[0].address, null)
      master_secret_arn = try(aws_db_instance.onboarding_postgres[0].master_user_secret[0].secret_arn, null)
      secret_prefix     = local.onboarding_secret_name
    }
    "paicing" = {
      enabled           = var.enable_paicing
      address           = try(aws_db_instance.paicing_postgres[0].address, null)
      master_secret_arn = try(aws_db_instance.paicing_postgres[0].master_user_secret[0].secret_arn, null)
      secret_prefix     = local.paicing_secret_name
    }
    "presentation-builder" = {
      enabled           = var.enable_presentation_builder
      address           = try(aws_db_instance.presentation_builder_postgres[0].address, null)
      master_secret_arn = try(aws_db_instance.presentation_builder_postgres[0].master_user_secret[0].secret_arn, null)
      secret_prefix     = local.presentation_builder_secret_name
    }
  }

  # Keys depend only on feature flags, so they are known at plan time and safe
  # to use with for_each.
  database_access_targets = var.enable_database_access ? {
    for key, db in local.database_access_candidates : key => db if db.enabled
  } : {}
}

data "aws_ssm_parameter" "database_access_ami" {
  count = var.enable_database_access ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "database_access" {
  count = var.enable_database_access ? 1 : 0

  name        = "${local.name}-database-access"
  description = "SSM jump instance for human PostgreSQL access. No inbound rules."
  vpc_id      = module.vpc.vpc_id

  # Explicitly empty: Session Manager needs no inbound access, and declaring
  # it makes Terraform remove any rule someone adds by hand.
  ingress = []

  egress {
    description = "PostgreSQL inside the VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to the SSM, EC2 Messages and SSM Messages endpoints via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "database_access_instance_assume" {
  count = var.enable_database_access ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "database_access_instance" {
  count = var.enable_database_access ? 1 : 0

  name               = "${local.name}-database-access-instance"
  assume_role_policy = data.aws_iam_policy_document.database_access_instance_assume[0].json
}

resource "aws_iam_role_policy_attachment" "database_access_instance_ssm" {
  count = var.enable_database_access ? 1 : 0

  role       = aws_iam_role.database_access_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "database_access" {
  count = var.enable_database_access ? 1 : 0

  name = "${local.name}-database-access"
  role = aws_iam_role.database_access_instance[0].name
}

resource "aws_instance" "database_access" {
  count = var.enable_database_access ? 1 : 0

  ami                    = data.aws_ssm_parameter.database_access_ami[0].value
  instance_type          = var.database_access_instance_type
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.database_access[0].id]
  iam_instance_profile   = aws_iam_instance_profile.database_access[0].name

  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-database-access"
  }

  lifecycle {
    # A new AL2023 AMI is published regularly; picking it up must be a
    # deliberate replacement (taint), not a side effect of an unrelated apply.
    ignore_changes = [ami]
  }
}

# Containers for the read-only credentials. Terraform never writes the value:
# an admin creates the password together with the Postgres role (see
# docs/database-access.md), so it never reaches Terraform state.
resource "aws_secretsmanager_secret" "database_readonly" {
  for_each = local.database_access_targets

  name        = "${each.value.secret_prefix}/db-readonly"
  description = "Read-only PostgreSQL login for ${each.key} (${var.environment}). JSON keys: username, password. Populated by an admin; Terraform never writes values."

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

data "aws_iam_policy_document" "database_access_tunnel" {
  count = var.enable_database_access ? 1 : 0

  statement {
    sid     = "StartPortForwardOnJumpInstanceOnly"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.database_access[0].arn,
      "arn:aws:ssm:${var.aws_region}::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]

    # Forces Session Manager to check the document against this policy, so the
    # default shell document (SSM-SessionManagerRunShell) is refused.
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
  }

  statement {
    sid       = "ManageSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:session/*"]
  }

  statement {
    sid = "FindJumpInstance"
    actions = [
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation",
      "ssm:DescribeSessions",
      "rds:DescribeDBInstances",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "database_admin_access" {
  count = var.enable_database_access ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.database_access_tunnel[0].json]

  # Both secret types use the AWS-managed default KMS key, so no kms:Decrypt
  # grant is needed.
  statement {
    sid     = "ReadMasterAndReadonlyCredentials"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat(
      [for db in local.database_access_targets : db.master_secret_arn],
      [for secret in aws_secretsmanager_secret.database_readonly : secret.arn],
    )
  }

  # Lets an admin set the read-only password after creating the Postgres role.
  statement {
    sid       = "SetReadonlyCredentials"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [for secret in aws_secretsmanager_secret.database_readonly : secret.arn]
  }
}

data "aws_iam_policy_document" "database_readonly_access" {
  count = var.enable_database_access ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.database_access_tunnel[0].json]

  statement {
    sid       = "ReadReadonlyCredentials"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [for secret in aws_secretsmanager_secret.database_readonly : secret.arn]
  }
}

# Stable names: Identity Center permission sets reference customer-managed
# policies by name, and the policy must exist in this account under that name.
resource "aws_iam_policy" "database_admin_access" {
  count = var.enable_database_access ? 1 : 0

  name        = "${local.name}-database-admin-access"
  description = "SSM tunnel to the ${var.environment} PostgreSQL instances and read access to their RDS-managed master credentials."
  policy      = data.aws_iam_policy_document.database_admin_access[0].json
}

resource "aws_iam_policy" "database_readonly_access" {
  count = var.enable_database_access ? 1 : 0

  name        = "${local.name}-database-readonly-access"
  description = "SSM tunnel to the ${var.environment} PostgreSQL instances and read access to their read-only credentials."
  policy      = data.aws_iam_policy_document.database_readonly_access[0].json
}
