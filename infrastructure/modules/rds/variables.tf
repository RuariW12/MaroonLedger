
variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}


variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "database_subnet_group_name" {
  description = "Name of the database subnet group from VPC module"
  type        = string
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
}
