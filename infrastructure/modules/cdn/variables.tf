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

variable "enable_waf" {
  description = "Attach a WAF web ACL to the distribution. Set false only where an SCP denies wafv2 at CloudFront scope; the distribution then serves without one."
  type        = bool
  default     = true
}

variable "bucket_suffix" {
  description = "Suffix for the frontend bucket. S3 names are global, so a bare project name collides with any account that has ever used it."
  type        = string
  default     = ""
}
