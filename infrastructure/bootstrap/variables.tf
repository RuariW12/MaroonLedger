variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "region" {
  description = "AWS region for the state infrastructure"
  type        = string
  default     = "us-east-2"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket. S3 names are global, so this carries a random suffix rather than the account ID -- the ID would otherwise be published in this repo."
  type        = string
  default     = "maroon-ledger-tfstate-4cc78b"
}
