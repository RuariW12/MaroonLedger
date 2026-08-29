variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}

variable "alb_ingress_ports" {
  description = "Ports the ALB accepts from CloudFront. Each prefix-list rule consumes ~55 of the 60-rule-per-SG quota, so list only the port actually in use: 80 without a certificate, 443 with one."
  type        = list(number)
  default     = [80]
}
