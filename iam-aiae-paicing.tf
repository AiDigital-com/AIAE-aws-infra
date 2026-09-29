# IAM for Pacing: one role for GitHub Actions (build and publish artifacts) and
# one for the workload itself (IRSA). Neither can do the other's job, and
# neither receives Kubernetes credentials — Argo CD, not CI, reconciles the
# cluster.

# ---------------------------------------------------------------------------
# GitHub Actions CI role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "paicing_github_oidc_assume_role" {
  count = var.enable_paicing ? 1 : 0

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

    # StringEquals, not StringLike: the subjects are exact and must stay that
    # way. A wildcard here would let any repository or branch in the
    # organization assume a role that can push production images.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.paicing_github_subjects
    }
  }
}

data "aws_iam_policy_document" "paicing_github_ci" {
  count = var.enable_paicing ? 1 : 0

  # ecr:GetAuthorizationToken is account-scoped by AWS and cannot be narrowed
  # to a repository.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrRepositoryRead"
    effect    = "Allow"
    actions   = ["ecr:DescribeRepositories"]
    resources = ["*"]
  }

  # BatchGetImage and DescribeImages are required beyond a plain push: buildx
  # reads the existing manifest, the deploy workflows check whether an
  # immutable tag already exists before rebuilding, and the rollback workflow
  # resolves all four tags to digests before it will repin anything. Omitting
  # them produces a push that fails late, after the layers have uploaded.
  statement {
    sid    = "EcrPushPaicing"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.paicing[0].arn]
  }

  # No S3 or CloudFront statements: the workspace/ SPA was retired and is
  # neither built nor served, so Pacing deploys no frontend. No
  # secretsmanager:GetSecretValue either — unlike the Onboarding Platform,
  # nothing in Pacing's build reads configuration, because there is no
  # browser bundle to embed a public key into.
}

resource "aws_iam_role" "paicing_github_ci" {
  count = var.enable_paicing ? 1 : 0

  name               = "${local.paicing_name}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.paicing_github_oidc_assume_role[0].json

  lifecycle {
    precondition {
      condition     = length(var.paicing_github_oidc_subjects) > 0
      error_message = "paicing_github_oidc_subjects must list the exact environment subjects; an empty list would produce a role nothing can assume."
    }
  }
}

resource "aws_iam_policy" "paicing_github_ci" {
  count = var.enable_paicing ? 1 : 0

  name   = "${local.paicing_name}-github-ci"
  policy = data.aws_iam_policy_document.paicing_github_ci[0].json
}

resource "aws_iam_role_policy_attachment" "paicing_github_ci" {
  count = var.enable_paicing ? 1 : 0

  role       = aws_iam_role.paicing_github_ci[0].name
  policy_arn = aws_iam_policy.paicing_github_ci[0].arn
}

# ---------------------------------------------------------------------------
# Workload role (IRSA)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "paicing_application_assume_role" {
  count = var.enable_paicing ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = local.paicing_application_service_account_subjects
    }
  }
}

data "aws_iam_policy_document" "paicing_application" {
  count = var.enable_paicing ? 1 : 0

  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.paicing[0].arn]
  }

  # Deliberately NOT the RDS master secret. The application logs in as its own
  # least-privilege database role, whose DSN lives in the secret above; the
  # master credentials belong to the migration Job alone. Granting them here
  # would let a pod that may only read and write rows also alter the schema.
  #
  # Nothing else either: Pacing reaches BigQuery and Google Sheets with a Google
  # service-account key held in its own secret, not with AWS credentials, and it
  # writes its dashboard cache to a Kubernetes volume rather than to S3.
}

resource "aws_iam_role" "paicing_application" {
  count = var.enable_paicing ? 1 : 0

  name               = "${local.paicing_name}-application"
  assume_role_policy = data.aws_iam_policy_document.paicing_application_assume_role[0].json
}

resource "aws_iam_role_policy" "paicing_application" {
  count = var.enable_paicing ? 1 : 0

  name   = "${local.paicing_name}-application"
  role   = aws_iam_role.paicing_application[0].id
  policy = data.aws_iam_policy_document.paicing_application[0].json
}

# ---------------------------------------------------------------------------
# Migration Job role (IRSA)
# ---------------------------------------------------------------------------
# Separate from the application role because this is the only identity that
# needs the RDS master credentials: it applies the schema, and it reconciles
# the application's own database role against the DSN in the application
# secret. A Job Pod is created fresh for every sync, so its projected mount
# always holds the current master password — which is what makes the seven-day
# AWS rotation a non-event here.

data "aws_iam_policy_document" "paicing_migrate_assume_role" {
  count = var.enable_paicing ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = local.paicing_migrate_service_account_subjects
    }
  }
}

data "aws_iam_policy_document" "paicing_migrate" {
  count = var.enable_paicing ? 1 : 0

  # Host, port and database name, plus the application DSN whose role and
  # password this Job reconciles.
  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.paicing[0].arn]
  }

  statement {
    sid    = "ReadDatabaseMasterSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_db_instance.paicing_postgres[0].master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role" "paicing_migrate" {
  count = var.enable_paicing ? 1 : 0

  name               = "${local.paicing_name}-migrate"
  assume_role_policy = data.aws_iam_policy_document.paicing_migrate_assume_role[0].json
}

resource "aws_iam_role_policy" "paicing_migrate" {
  count = var.enable_paicing ? 1 : 0

  name   = "${local.paicing_name}-migrate"
  role   = aws_iam_role.paicing_migrate[0].id
  policy = data.aws_iam_policy_document.paicing_migrate[0].json
}
