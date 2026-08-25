# AIAE AWS Infrastructure

Terraform for the shared AIAE AWS platform. Operational Hub is the first application; additional AIAE applications can be added without creating new infrastructure repositories.

## Repository boundaries

- This repository owns AWS infrastructure and EKS/Argo CD bootstrap resources.
- `AIAE-helm` owns reusable application Helm charts.
- `AIAE-helm-versions` owns environment values and deployed image tags.
- Each application repository owns build/test, Maven Liquibase, image push, and the GitOps tag update.

## Accounts

| Environment | AWS account | Region | Terraform profile |
| --- | --- | --- | --- |
| dev | `496336474487` | `us-east-1` | `aiae-dev` |
| prod | `125093118532` | `us-east-1` | `aiae-prod` |

Every account has independent VPC, EKS, ECR, RDS, Secrets Manager, GitHub OIDC, CodeConnections, and Terraform state resources. Nothing is shared across the dev/prod account boundary.

## Operational Hub resources

Each environment stack creates:

- VPC with public, private, and database subnets, NAT gateways, and VPC flow logs.
- EKS Auto Mode with control-plane CloudWatch logs and IRSA enabled.
- Private RDS PostgreSQL with managed master credentials, backups, log exports, and alarms.
- ECR repository `aidigital.aiae-projects/operational-hub-application`.
- Secrets Manager container `AIAE-DEV/operational-hub` or `AIAE-PRD/operational-hub`.
- Application IAM role restricted to the environment secret.
- Secrets Store CSI driver/provider with Kubernetes Secret synchronization and rotation.
- EKS Auto Mode ALB `IngressClass` and `IngressClassParams`.
- GitHub Actions OIDC role for ECR push and migration-secret read.

Optional feature flags add:

- AWS-managed Argo CD capability with Identity Center mappings.
- GitHub CodeConnections authentication and Argo CD GitOps bootstrap.
- ACM certificate, Route53 DNS validation, and ExternalDNS when a Route53 zone is available.
- Private S3 + CloudFront frontend hosting.

## Prerequisites

- Terraform 1.8 or newer.
- AWS CLI v2, because the Helm provider uses `aws eks get-token`.
- CLI profiles `aiae-dev` and `aiae-prod`, preferably backed by IAM Identity Center.
- Platform-provisioning permissions in both accounts.

No AWS access keys are stored in GitHub. GitHub Actions assumes Terraform-created roles through OIDC.

## 1. Bootstrap remote state

Bootstrap each account independently. The explicit account ID and profile prevent applying to the wrong account.

```bash
cd bootstrap

AWS_PROFILE=aiae-dev terraform init
AWS_PROFILE=aiae-dev terraform workspace select -or-create dev
AWS_PROFILE=aiae-dev terraform plan -var-file=env/dev.tfvars
AWS_PROFILE=aiae-dev terraform apply -var-file=env/dev.tfvars

AWS_PROFILE=aiae-prod terraform workspace select -or-create prod
AWS_PROFILE=aiae-prod terraform plan -var-file=env/prod.tfvars
AWS_PROFILE=aiae-prod terraform apply -var-file=env/prod.tfvars

cd ..
```

This creates one state bucket and lock table per account. The root backend files already reference their names.

## 2. Apply base infrastructure

Dev:

```bash
AWS_PROFILE=aiae-dev terraform init -reconfigure -backend-config=backend-config/dev.hcl
AWS_PROFILE=aiae-dev terraform plan -var-file=env/dev.tfvars
AWS_PROFILE=aiae-dev terraform apply -var-file=env/dev.tfvars
```

Prod:

```bash
AWS_PROFILE=aiae-prod terraform init -reconfigure -backend-config=backend-config/prod.hcl
AWS_PROFILE=aiae-prod terraform plan -var-file=env/prod.tfvars
AWS_PROFILE=aiae-prod terraform apply -var-file=env/prod.tfvars
```

The initial base apply leaves Argo CD, DNS, and frontend flags disabled until their external inputs are available.

## 3. Configure GitHub and Argo CD

In each account, set `create_github_codeconnection = true` and apply once. AWS creates the connection in `PENDING`; complete its GitHub authorization in the AWS CodeConnections console. Terraform cannot complete that OAuth handshake.

Get the IAM Identity Center instance ARN and group/user IDs, then configure the matching environment:

```hcl
enable_argocd           = true
enable_gitops_bootstrap = true
argocd_idc_instance_arn = "arn:aws:sso:::instance/ssoins-..."

argocd_rbac_role_mappings = {
  platform_admins = {
    role = "ADMIN"
    identities = [{
      id   = "identity-center-group-id"
      type = "SSO_GROUP"
    }]
  }
}
```

The capability role receives only `GetConnection` and `UseConnection` for its account's connection. Terraform then creates the managed Argo CD capability, registers the local EKS cluster, and creates the environment AppProject and Application.

## 4. DNS and TLS

The current domain is managed in GoDaddy, not Route53, so DNS flags remain disabled. Before HTTPS go-live, choose one approach:

- create an ACM certificate and add its DNS validation CNAME plus the application CNAME manually in GoDaddy; or
- delegate an AIAE subdomain to a Route53 hosted zone and enable the existing Terraform DNS resources.

The proposed dev hostname is `dev.aiae-operational-hub.aidigital.tech`. Do not enable `route53_zone_name`, `enable_public_certificate`, or `enable_external_dns` until the DNS approach is selected and represented in Terraform.

## 5. Populate application secrets

Terraform creates the secret container but never writes secret values into Terraform state. Populate each environment secret as JSON:

```json
{
  "POSTGRES_HOST": "database-host",
  "POSTGRES_PORT": "5432",
  "POSTGRES_DB": "operational_hub",
  "POSTGRES_USER": "operational_hub",
  "POSTGRES_PASSWORD": "database-password",
  "GOOGLE_SERVICE_ACCOUNT_JSON": "{}"
}
```

Use these Terraform outputs:

- `rds_endpoint`
- `rds_port`
- `rds_master_user_secret_arn`
- `secrets_manager_secret_name`
- `application_iam_role_arn`

Set `application_iam_role_arn` as the `eks.amazonaws.com/role-arn` service-account annotation in the matching `AIAE-helm-versions` branch.

## 6. Configure GitHub Actions

Create GitHub environments `dev` and `prod` in each application repository with:

- `AWS_REGION=us-east-1`
- `AWS_BACKEND_CI_ROLE_TO_ASSUME=<github_backend_ci_role_arn>`
- `GITOPS_VERSIONS_REPOSITORY=AiDigital-com/AIAE-helm-versions`
- secret `GITOPS_TOKEN`

## Liquibase network requirement

RDS is private. A GitHub-hosted runner cannot reach it even with correct IAM permissions. Maven Liquibase must run from an execution environment inside the VPC before the workflow updates the GitOps image tag.

## Optional frontend

`enable_frontend = true` creates a private S3 bucket and CloudFront distribution. Leave `frontend_domain_name` empty to use the generated CloudFront hostname. A custom frontend hostname must differ from the API/ALB hostname.

## Local validation

These commands do not call AWS APIs:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
helm lint charts/cluster-bootstrap
```
