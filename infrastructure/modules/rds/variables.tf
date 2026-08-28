
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

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "maroonledger"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "dbadmin"
}

variable "enable_password_rotation" {
  description = "Let RDS rotate the master password automatically"
  type        = bool
  default     = true
}

variable "password_rotation_days" {
  description = "How often RDS rotates the master password, in days"
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "Block accidental deletion of the instance. Leave false while tearing the environment down repeatedly."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. False is correct for anything holding real data."
  type        = bool
  default     = true
}
