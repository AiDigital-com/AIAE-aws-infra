output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Use this bucket in backend-config/dev.hcl and backend-config/prod.hcl."
}

output "lock_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "Use this table in backend-config/dev.hcl and backend-config/prod.hcl."
}
