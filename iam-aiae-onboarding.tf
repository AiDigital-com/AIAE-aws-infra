# IAM for the AIAE Onboarding Platform: one role for GitHub Actions (build and
# publish artifacts) and one role for the workload itself (IRSA). Neither can
# do the other's job, and neither receives Kubernetes credentials — Argo CD,
# not CI, reconciles the cluster.

# ---------------------------------------------------------------------------
# GitHub Actions CI role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "onboarding_github_oidc_assume_role" {
  count = var.enable_onboarding_platform ? 1 : 0

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
      values   = local.onboarding_github_subjects
    }
  }
}

data "aws_iam_policy_document" "onboarding_github_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

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
    sid    = "EcrPushOnboarding"
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
    resources = [aws_ecr_repository.onboarding[0].arn]
  }

  statement {
    sid    = "ReadApplicationBuildConfig"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.onboarding[0].arn]
  }
}

data "aws_iam_policy_document" "onboarding_github_frontend_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

  statement {
    sid       = "ListFrontendBucket"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.onboarding_frontend[0].arn]
  }

  statement {
    sid    = "DeployFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.onboarding_frontend[0].arn}/*"]
  }

  statement {
    sid       = "InvalidateFrontendCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.onboarding_frontend[0].arn]
  }
}

resource "aws_iam_role" "onboarding_github_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

  name               = "${local.onboarding_name}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.onboarding_github_oidc_assume_role[0].json

  lifecycle {
    precondition {
      condition     = length(var.onboarding_github_oidc_subjects) > 0
      error_message = "onboarding_github_oidc_subjects must list the exact environment subjects; an empty list would produce a role nothing can assume."
    }
  }
}

resource "aws_iam_policy" "onboarding_github_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

  name   = "${local.onboarding_name}-github-ci"
  policy = data.aws_iam_policy_document.onboarding_github_ci[0].json
}

resource "aws_iam_role_policy_attachment" "onboarding_github_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

  role       = aws_iam_role.onboarding_github_ci[0].name
  policy_arn = aws_iam_policy.onboarding_github_ci[0].arn
}

resource "aws_iam_role_policy" "onboarding_github_frontend_ci" {
  count = var.enable_onboarding_platform ? 1 : 0

  name   = "${local.onboarding_name}-github-frontend-ci"
  role   = aws_iam_role.onboarding_github_ci[0].id
  policy = data.aws_iam_policy_document.onboarding_github_frontend_ci[0].json
}

# ---------------------------------------------------------------------------
# Workload role (IRSA)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "onboarding_application_assume_role" {
  count = var.enable_onboarding_platform ? 1 : 0

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
      values   = local.onboarding_service_account_subjects
    }
  }
}

data "aws_iam_policy_document" "onboarding_application" {
  count = var.enable_onboarding_platform ? 1 : 0

  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.onboarding[0].arn]
  }

  # The application presigns S3 URLs so the browser uploads and downloads
  # material files directly. Presigning is a local signing operation, but it
  # signs with THESE credentials, so the role must actually hold the object
  # permissions the presigned URL grants.
  statement {
    sid       = "ListMaterialsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.onboarding_materials[0].arn]
  }

  statement {
    sid    = "ReadWriteMaterialObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.onboarding_materials[0].arn}/*"]
  }
}

resource "aws_iam_role" "onboarding_application" {
  count = var.enable_onboarding_platform ? 1 : 0

  name               = "${local.onboarding_name}-application"
  assume_role_policy = data.aws_iam_policy_document.onboarding_application_assume_role[0].json

  # Presigned GET URLs are signed with this role's temporary credentials and
  # stop working when the session expires, regardless of the URL's own expiry.
  # One hour is the IRSA default; raising it here keeps app.external.storage
  # .presign-get-expires-seconds honest.
  max_session_duration = 43200
}

resource "aws_iam_role_policy" "onboarding_application" {
  count = var.enable_onboarding_platform ? 1 : 0

  name   = "${local.onboarding_name}-application"
  role   = aws_iam_role.onboarding_application[0].id
  policy = data.aws_iam_policy_document.onboarding_application[0].json
}
