resource "aws_codeconnections_connection" "github" {
  count = var.create_github_codeconnection ? 1 : 0

  name          = "aiae-github"
  provider_type = "GitHub"
}

data "aws_iam_policy_document" "argocd_capability_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["capabilities.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "argocd_capability" {
  dynamic "statement" {
    for_each = var.create_github_codeconnection || var.github_codeconnection_arn != "" ? [1] : []

    content {
      sid    = "ReadGitHubRepositories"
      effect = "Allow"
      actions = [
        "codeconnections:GetConnection",
        "codeconnections:UseConnection",
      ]
      resources = [local.github_codeconnection_arn]
    }
  }
}

resource "aws_iam_role" "argocd_capability" {
  count = var.enable_argocd ? 1 : 0

  name               = "${local.name}-argocd-capability"
  assume_role_policy = data.aws_iam_policy_document.argocd_capability_assume_role.json
}

resource "aws_iam_role_policy" "argocd_capability" {
  count = var.enable_argocd && (var.create_github_codeconnection || var.github_codeconnection_arn != "") ? 1 : 0

  name   = "${local.name}-argocd-sources"
  role   = aws_iam_role.argocd_capability[0].id
  policy = data.aws_iam_policy_document.argocd_capability.json
}

resource "aws_eks_capability" "argocd" {
  count = var.enable_argocd ? 1 : 0

  cluster_name              = module.eks.cluster_name
  capability_name           = "argocd"
  type                      = "ARGOCD"
  role_arn                  = aws_iam_role.argocd_capability[0].arn
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      namespace = "argocd"

      aws_idc {
        idc_instance_arn = var.argocd_idc_instance_arn
        idc_region       = var.argocd_idc_region == "" ? var.aws_region : var.argocd_idc_region
      }

      dynamic "rbac_role_mapping" {
        for_each = var.argocd_rbac_role_mappings

        content {
          role = rbac_role_mapping.value.role

          dynamic "identity" {
            for_each = rbac_role_mapping.value.identities

            content {
              id   = identity.value.id
              type = identity.value.type
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws:sso:::instance/ssoins-[A-Za-z0-9]+$", var.argocd_idc_instance_arn))
      error_message = "argocd_idc_instance_arn must be a valid IAM Identity Center instance ARN when enable_argocd=true."
    }

    precondition {
      condition     = length(var.argocd_rbac_role_mappings) > 0
      error_message = "At least one Identity Center ADMIN/EDITOR/VIEWER mapping is required when enable_argocd=true."
    }
  }
}

resource "aws_eks_access_policy_association" "argocd_cluster_view" {
  count = var.enable_argocd ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_capability[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.argocd]
}

resource "aws_eks_access_policy_association" "argocd_namespace_admin" {
  count = var.enable_argocd ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_capability[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [local.app_namespace]
  }

  depends_on = [aws_eks_capability.argocd]
}
