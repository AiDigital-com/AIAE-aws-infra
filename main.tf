data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

data "aws_iam_policy_document" "github_backend_ci" {
  statement {
    sid    = "EcrAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrRepositoryRead"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushOperationalHub"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      local.ecr_repository_arn,
    ]
  }

}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]
}

data "aws_ecr_repository" "backend" {
  count = var.create_ecr_repository ? 0 : 1

  name = local.ecr_repository_name
}

resource "aws_iam_role" "github_backend_ci" {
  name               = "${local.name}-github-backend-ci"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json
}

resource "aws_iam_policy" "github_backend_ci" {
  name   = "${local.name}-github-backend-ci"
  policy = data.aws_iam_policy_document.github_backend_ci.json
}

resource "aws_iam_role_policy_attachment" "github_backend_ci" {
  role       = aws_iam_role.github_backend_ci.name
  policy_arn = aws_iam_policy.github_backend_ci.arn
}

data "aws_iam_policy_document" "github_frontend_ci" {
  count = var.enable_frontend ? 1 : 0

  statement {
    sid     = "ListFrontendBucket"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.frontend[0].arn,
    ]
  }

  statement {
    sid    = "DeployFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.frontend[0].arn}/*",
    ]
  }

  statement {
    sid     = "InvalidateFrontendCache"
    effect  = "Allow"
    actions = ["cloudfront:CreateInvalidation"]
    resources = [
      aws_cloudfront_distribution.frontend[0].arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_frontend_ci" {
  count = var.enable_frontend ? 1 : 0

  name   = "${local.name}-github-frontend-ci"
  role   = aws_iam_role.github_backend_ci.id
  policy = data.aws_iam_policy_document.github_frontend_ci[0].json
}

resource "aws_ecr_repository" "backend" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = local.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.backend[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 50 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = var.vpc_cidr

  azs              = var.availability_zones
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_iam_role             = true
  create_flow_log_cloudwatch_log_group            = true
  flow_log_cloudwatch_log_group_retention_in_days = var.eks_cloudwatch_log_retention_days

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Allow PostgreSQL from VPC workloads"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.eks_endpoint_public_access_cidrs

  deletion_protection = var.enable_deletion_protection

  create_kms_key    = false
  encryption_config = null

  cloudwatch_log_group_retention_in_days = var.eks_cloudwatch_log_retention_days

  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name}-postgres"
  subnet_ids = module.vpc.database_subnets
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.database_instance_class

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = var.database_allocated_storage * 2
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  backup_retention_period   = var.environment == "prod" ? 14 : 3
  deletion_protection       = var.enable_deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name}-postgres-final" : null

  performance_insights_enabled = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  depends_on = [
    aws_cloudwatch_log_group.rds_postgresql,
    aws_cloudwatch_log_group.rds_upgrade,
  ]
}

resource "aws_secretsmanager_secret" "app" {
  name        = local.secret_name
  description = "Operational Hub ${var.environment} application runtime values. Populate SecretString manually or via a secure break-glass process."

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}
