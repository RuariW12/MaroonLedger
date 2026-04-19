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
