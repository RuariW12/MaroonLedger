variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "alb_dns_name" {
  description = "DNS name of the ALB for the API origin"
  type        = string
}
