resource "helm_release" "secrets_store_csi" {
  count = var.enable_secrets_store_csi ? 1 : 0

  name       = "secrets-provider-aws"
  namespace  = "kube-system"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = "3.1.2"

  atomic  = true
  timeout = 600
  wait    = true

  values = [yamlencode({
    secrets-store-csi-driver = {
      install = true
      syncSecret = {
        enabled = true
      }
      enableSecretRotation = true
      rotationPollInterval = "3600s"
    }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.21.1"

  atomic  = true
  timeout = 600
  wait    = true

  values = [yamlencode({
    provider = {
      name = "aws"
    }
    sources       = ["ingress"]
    policy        = "upsert-only"
    registry      = "txt"
    txtOwnerId    = local.name
    domainFilters = [trimsuffix(var.route53_zone_name, ".")]
    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
      }
    }
  })]

  depends_on = [
    module.eks,
    aws_iam_role_policy.external_dns,
  ]
}

resource "helm_release" "cluster_bootstrap" {
  name      = "${local.name}-bootstrap"
  namespace = "kube-system"
  chart     = "${path.module}/charts/cluster-bootstrap"

  atomic  = true
  timeout = 600
  wait    = true

  values = [yamlencode({
    ingress = {
      enabled         = true
      className       = "alb"
      scheme          = "internet-facing"
      publicSubnetIds = module.vpc.public_subnets
      certificateARNs = var.enable_public_certificate ? [aws_acm_certificate_validation.api[0].certificate_arn] : []
      tags            = local.tags
    }
    argocd = {
      enabled                = var.enable_argocd
      namespace              = "argocd"
      clusterArn             = module.eks.cluster_arn
      targetNamespace        = local.app_namespace
      projectName            = local.name
      gitopsBootstrapEnabled = var.enable_gitops_bootstrap
      helmRepositoryUrl      = local.gitops_helm_repository_url
      versionsRepositoryUrl  = local.gitops_versions_repository_url
      targetRevision         = var.environment
    }
  })]

  lifecycle {
    precondition {
      condition = !var.enable_gitops_bootstrap || (
        var.enable_argocd &&
        local.gitops_helm_repository_url != "" &&
        local.gitops_versions_repository_url != ""
      )
      error_message = "GitOps bootstrap requires Argo CD and both Git repository URLs (explicit or derived from CodeConnections)."
    }
  }

  depends_on = [
    module.eks,
    aws_eks_capability.argocd,
    aws_eks_access_policy_association.argocd_cluster_view,
    aws_eks_access_policy_association.argocd_namespace_edit,
  ]
}
