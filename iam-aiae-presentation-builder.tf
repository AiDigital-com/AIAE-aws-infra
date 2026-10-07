# IAM for the AIAE Presentation Builder: one role for GitHub Actions (build and
# publish artifacts) and one role for the workload itself (IRSA). Neither can
# do the other's job, and neither receives Kubernetes credentials — Argo CD,
# not CI, reconciles the cluster.

# ---------------------------------------------------------------------------
# GitHub Actions CI role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "presentation_builder_github_oidc_assume_role" {
  count = var.enable_presentation_builder ? 1 : 0

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
    # way. AIAE-presentation-builder is a PUBLIC repository, so a wildcard here
    # would let any fork-triggered or unrelated workflow in the organization
    # assume a role that can publish images.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.presentation_builder_github_subjects
    }
  }
}

data "aws_iam_policy_document" "presentation_builder_github_ci" {
  count = var.enable_presentation_builder ? 1 : 0

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
  # reads the existing manifest, and the release workflow checks whether an
  # immutable tag already exists before rebuilding. Omitting them produces a
  # push that fails late, after the image layers have already uploaded.
  statement {
    sid    = "EcrPushPresentationBuilder"
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
    resources = [aws_ecr_repository.presentation_builder[0].arn]
  }

  # The frontend bakes CLERK_PUBLISHABLE_KEY into the bundle at build time
  # (vite.config.ts `define`), so the workflow must read it before `npm run
  # build`. It is public once compiled, but sourcing it from the environment's
  # secret keeps DEV and PROD from drifting apart.
  statement {
    sid    = "ReadApplicationBuildConfig"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.presentation_builder[0].arn]
  }
}

data "aws_iam_policy_document" "presentation_builder_github_frontend_ci" {
  count = var.enable_presentation_builder ? 1 : 0

  statement {
    sid       = "ListFrontendBucket"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.presentation_builder_frontend[0].arn]
  }

  statement {
    sid    = "DeployFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.presentation_builder_frontend[0].arn}/*"]
  }

  statement {
    sid       = "InvalidateFrontendCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.presentation_builder_frontend[0].arn]
  }
}

resource "aws_iam_role" "presentation_builder_github_ci" {
  count = var.enable_presentation_builder ? 1 : 0

  name               = "${local.presentation_builder_name}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.presentation_builder_github_oidc_assume_role[0].json

  lifecycle {
    precondition {
      condition     = length(var.presentation_builder_github_oidc_subjects) > 0
      error_message = "presentation_builder_github_oidc_subjects must list the exact environment subjects; an empty list would produce a role nothing can assume."
    }
  }
}

resource "aws_iam_policy" "presentation_builder_github_ci" {
  count = var.enable_presentation_builder ? 1 : 0

  name   = "${local.presentation_builder_name}-github-ci"
  policy = data.aws_iam_policy_document.presentation_builder_github_ci[0].json
}

resource "aws_iam_role_policy_attachment" "presentation_builder_github_ci" {
  count = var.enable_presentation_builder ? 1 : 0

  role       = aws_iam_role.presentation_builder_github_ci[0].name
  policy_arn = aws_iam_policy.presentation_builder_github_ci[0].arn
}

resource "aws_iam_role_policy" "presentation_builder_github_frontend_ci" {
  count = var.enable_presentation_builder ? 1 : 0

  name   = "${local.presentation_builder_name}-github-frontend-ci"
  role   = aws_iam_role.presentation_builder_github_ci[0].id
  policy = data.aws_iam_policy_document.presentation_builder_github_frontend_ci[0].json
}

# ---------------------------------------------------------------------------
# Workload role (IRSA)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "presentation_builder_application_assume_role" {
  count = var.enable_presentation_builder ? 1 : 0

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
      values   = local.presentation_builder_service_account_subjects
    }
  }
}

data "aws_iam_policy_document" "presentation_builder_application" {
  count = var.enable_presentation_builder ? 1 : 0

  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.presentation_builder[0].arn]
  }

  # AWS owns the database password: it rotates it into the RDS-managed master
  # user secret every seven days, and that schedule is not ours to stop. So the
  # application reads the credentials from that secret directly through the AWS
  # Advanced JDBC Wrapper rather than from a copy in the secret above. A copy is
  # what broke Operational Hub and the Onboarding Platform in September 2026:
  # nothing updated it, and a pod holds its environment for its whole life, so
  # the stale value kept failing until someone intervened.
  #
  # Both the application and the Liquibase PreSync Job need this: the Job gets
  # the same credentials projected as files by the Secrets Store CSI driver, and
  # both service accounts assume this role (see
  # local.presentation_builder_service_account_subjects).
  statement {
    sid    = "ReadDatabaseCredentialsSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_db_instance.presentation_builder_postgres[0].master_user_secret[0].secret_arn]
  }

  # No S3, BigQuery or other AWS API appears here. The application's generated
  # artifacts live in Google Slides and Google Sheets, reached with a Google
  # service account held in the application secret, and its only other outbound
  # integrations are Anthropic and Clerk. Granting unused AWS permissions would
  # widen the blast radius for nothing.
}

resource "aws_iam_role" "presentation_builder_application" {
  count = var.enable_presentation_builder ? 1 : 0

  name               = "${local.presentation_builder_name}-application"
  assume_role_policy = data.aws_iam_policy_document.presentation_builder_application_assume_role[0].json
}

resource "aws_iam_role_policy" "presentation_builder_application" {
  count = var.enable_presentation_builder ? 1 : 0

  name   = "${local.presentation_builder_name}-application"
  role   = aws_iam_role.presentation_builder_application[0].id
  policy = data.aws_iam_policy_document.presentation_builder_application[0].json
}
