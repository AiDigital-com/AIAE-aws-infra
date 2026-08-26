mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}
mock_provider "helm" {}

variables {
  aws_account_id = "496336474487"
  aws_region     = "us-east-1"
  github_org     = "AiDigital-com"

  vpc_cidr              = "10.40.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs   = ["10.40.0.0/24", "10.40.1.0/24"]
  private_subnet_cidrs  = ["10.40.10.0/24", "10.40.11.0/24"]
  database_subnet_cidrs = ["10.40.20.0/24", "10.40.21.0/24"]
}

override_module {
  target = module.vpc
  outputs = {
    vpc_id           = "vpc-12345678"
    public_subnets   = ["subnet-public-a", "subnet-public-b"]
    private_subnets  = ["subnet-private-a", "subnet-private-b"]
    database_subnets = ["subnet-database-a", "subnet-database-b"]
  }
}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "aiae-operational-hub-test"
    cluster_arn                        = "arn:aws:eks:us-east-1:496336474487:cluster/aiae-operational-hub-test"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "dGVzdA=="
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/test"
    oidc_provider_arn                  = "arn:aws:iam::496336474487:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/test"
  }
}

run "base_dev" {
  command = plan

  variables {
    environment                 = "dev"
    create_ecr_repository       = true
    create_github_oidc_provider = true
    enable_argocd               = false
    enable_gitops_bootstrap     = false
    enable_external_dns         = false
    enable_public_certificate   = false
    enable_frontend             = false
    enable_deletion_protection  = false
  }

  assert {
    condition     = aws_iam_role.application.name == "aiae-operational-hub-dev-application"
    error_message = "The dev application role name does not match the Helm environment."
  }

  assert {
    condition = local.github_subjects == [
      "repo:AiDigital-com/AIAE-operational-hub:environment:dev",
    ]
    error_message = "The dev GitHub OIDC trust must be limited to the dev environment."
  }

  assert {
    condition = local.application_service_account_subjects == [
      "system:serviceaccount:aiae-operational-hub-dev:operational-hub-api",
      "system:serviceaccount:aiae-operational-hub-dev:operational-hub-api-liquibase",
    ]
    error_message = "The application role must trust both runtime and Liquibase service accounts."
  }

  assert {
    condition     = length(aws_eks_capability.argocd) == 0
    error_message = "Argo CD must remain disabled in the base stack."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.frontend) == 0
    error_message = "Frontend resources must remain disabled in the base stack."
  }
}

run "full_prod" {
  command = plan

  variables {
    environment                  = "prod"
    vpc_cidr                     = "10.50.0.0/16"
    create_ecr_repository        = true
    create_github_oidc_provider  = true
    create_github_codeconnection = true

    enable_argocd           = true
    enable_gitops_bootstrap = true
    argocd_idc_instance_arn = "arn:aws:sso:::instance/ssoins-1234567890abcdef"
    argocd_rbac_role_mappings = {
      admins = {
        role = "ADMIN"
        identities = [{
          id   = "12345678-1234-1234-1234-123456789012"
          type = "SSO_GROUP"
        }]
      }
    }

    route53_zone_name         = "aidigital.tech"
    enable_public_certificate = true
    enable_external_dns       = true

    enable_frontend      = true
    frontend_domain_name = "hub.aidigital.tech"
  }

  assert {
    condition     = length(aws_eks_capability.argocd) == 1
    error_message = "The full stack must create the managed Argo CD capability."
  }

  assert {
    condition     = length(aws_eks_access_policy_association.argocd_cluster_view) == 1 && length(aws_eks_access_policy_association.argocd_namespace_edit) == 1
    error_message = "Argo CD target-cluster permissions are incomplete."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.frontend) == 1
    error_message = "The full stack must create CloudFront."
  }

  assert {
    condition     = length(aws_iam_role.external_dns) == 1
    error_message = "The full stack must create the ExternalDNS IAM role."
  }

  assert {
    condition = local.github_subjects == [
      "repo:AiDigital-com/AIAE-operational-hub:environment:prod",
    ]
    error_message = "The prod GitHub OIDC trust must be limited to the prod environment."
  }
}
