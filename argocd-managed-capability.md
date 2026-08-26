# AWS-managed Argo CD notes

The managed capability is implemented in `argocd.tf` and is controlled by `enable_argocd`.

Terraform creates the capability role, Identity Center role mappings, EKS capability, and target-cluster access policies. The local Helm bootstrap registers the EKS cluster using its ARN and creates the environment root Application. The root then follows the environment-specific app-of-apps configuration from the `dev` or `prod` branch of `AIAE-helm`.

External steps remain intentionally manual:

1. Approve the GitHub CodeConnections OAuth handshake in the AWS console.
2. Obtain the IAM Identity Center instance ARN and user/group IDs.
3. Confirm the connection is `AVAILABLE` before enabling GitOps bootstrap.
4. Confirm Argo CD reports the target cluster and repositories as connected.

The capability role has no ECR push, RDS, or application-secret permissions. It receives only repository-source permissions when a CodeConnections ARN is configured.

The EKS capability automatically creates its baseline access entry. This stack adds cluster-wide view plus edit access restricted to the environment namespace; it does not grant cluster-admin access.
