variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "alb_dns_name" {
  description = "DNS name of the ALB for the API origin"
  type        = string
}

variable "domain_name" {
  description = "Custom domain served by the distribution. Empty keeps the default *.cloudfront.net name."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for the custom domain. Empty uses the default CloudFront certificate."
  type        = string
  default     = ""
}

variable "alb_certificate_arn" {
  description = "Set when the ALB has a certificate, which switches the origin connection to HTTPS-only."
  type        = string
  default     = ""
}
