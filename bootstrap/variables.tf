variable "aws_region" {
  type        = string
  description = "AWS region for the Terraform state resources."
  default     = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account where the state resources must be created."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account id."
  }
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform state."
}
