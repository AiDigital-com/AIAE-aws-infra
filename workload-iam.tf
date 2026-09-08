data "aws_iam_policy_document" "application_assume_role" {
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
      values   = local.application_service_account_subjects
    }
  }
}

data "aws_iam_policy_document" "application" {
  statement {
    sid    = "ReadApplicationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.app.arn]
  }

  # AWS owns the database password: it rotates it into the RDS-managed master
  # user secret every seven days, and that schedule is not ours to stop while
  # RDS manages the password. So the application reads the credentials from
  # that secret directly through the AWS Advanced JDBC Wrapper rather than from
  # a copy in the secret above. The copy is what took this application down on
  # 3 September 2026: nothing updated it, and a pod holds its environment for
  # its whole life, so the stale value kept failing until someone intervened.
  # Reading the owner's copy at connection time removes the second source.
  #
  # Both the application and the Liquibase PreSync Job need this: the Job gets
  # the same credentials projected as files by the Secrets Store CSI driver, and
  # both service accounts assume this role (see
  # local.application_service_account_subjects).
  statement {
    sid    = "ReadDatabaseCredentialsSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_db_instance.postgres.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role" "application" {
  name               = "${local.name}-application"
  assume_role_policy = data.aws_iam_policy_document.application_assume_role.json
}

resource "aws_iam_role_policy" "application" {
  name   = "${local.name}-secrets-manager"
  role   = aws_iam_role.application.id
  policy = data.aws_iam_policy_document.application.json
}

data "aws_iam_policy_document" "fluent_bit_assume_role" {
  count = var.enable_application_logging ? 1 : 0

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
      values   = ["system:serviceaccount:kube-system:aws-for-fluent-bit"]
    }
  }
}

data "aws_iam_policy_document" "fluent_bit" {
  count = var.enable_application_logging ? 1 : 0

  statement {
    sid    = "WriteApplicationLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.application[0].arn}:*"]
  }
}

resource "aws_iam_role" "fluent_bit" {
  count = var.enable_application_logging ? 1 : 0

  name               = "${local.name}-fluent-bit"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume_role[0].json
}

resource "aws_iam_role_policy" "fluent_bit" {
  count = var.enable_application_logging ? 1 : 0

  name   = "${local.name}-cloudwatch-logs"
  role   = aws_iam_role.fluent_bit[0].id
  policy = data.aws_iam_policy_document.fluent_bit[0].json
}

data "aws_iam_policy_document" "external_dns_assume_role" {
  count = var.enable_external_dns ? 1 : 0

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
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  statement {
    sid    = "ChangeHostedZoneRecords"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.public[0].zone_id}"]
  }

  statement {
    sid    = "ReadHostedZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role[0].json

  lifecycle {
    precondition {
      condition     = var.route53_zone_name != ""
      error_message = "route53_zone_name must be set when enable_external_dns=true."
    }
  }
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name   = "${local.name}-route53"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}
