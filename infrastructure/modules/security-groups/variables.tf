variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}
