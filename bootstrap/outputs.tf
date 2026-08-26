output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Use this bucket in backend-config/dev.hcl and backend-config/prod.hcl."
}
