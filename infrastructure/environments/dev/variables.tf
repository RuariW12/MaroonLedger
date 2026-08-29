variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "container_image" {
  description = "Docker image URI for the app container. Leave empty to use the ECR repository this stack creates, tagged :latest -- which removes the chicken-and-egg of needing an image URI before the repository exists."
  type        = string
  default     = ""
}

variable "hosted_ui_domain_prefix" {
  description = "Globally unique prefix for the Cognito hosted UI domain"
  type        = string
}

variable "auth_callback_urls" {
  description = "URLs Cognito may redirect to after sign-in. Include the CloudFront domain once it is known."
  type        = list(string)
  default     = ["http://localhost:3001/"]
}

variable "auth_logout_urls" {
  description = "URLs Cognito may redirect to after sign-out"
  type        = list(string)
  default     = ["http://localhost:3001/"]
}

variable "cognito_advanced_security_mode" {
  description = "Cognito threat protection: OFF, AUDIT, or ENFORCED. AUDIT and ENFORCED are billed per monthly active user."
  type        = string
  default     = "OFF"
}

variable "ai_provider" {
  description = "AI backend for the deployed service: 'bedrock' or 'stub'"
  type        = string
  default     = "bedrock"
}

variable "bedrock_model" {
  description = "Bedrock model ID. Empty uses the application default."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain for the application, e.g. maroonledger.com. Empty disables Route 53, ACM, and the HTTPS listener; everything else applies normally."
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "Create the Route 53 hosted zone. Set false if the zone already exists."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT Gateway across both AZs. Saves ~$32/month; set false for production resilience."
  type        = bool
  default     = true
}

variable "create_vpc_endpoints" {
  description = "Create interface VPC endpoints. Each is billed hourly per AZ (~$7/month each here), so this is off by default."
  type        = bool
  default     = false
}

variable "enable_password_rotation" {
  description = "Let RDS rotate the database master password automatically"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Address subscribed to the alerts topic. The subscription must be confirmed by email before alerts arrive."
  type        = string
  default     = ""
}

variable "data_pipeline" {
  description = "Analytics emitter mode: 'off' or 'firehose'. Off by default; the data stack is a separate root module."
  type        = string
  default     = "off"
}

variable "data_pipeline_stream_arn" {
  description = "firehose_stream_arn output from the data stack. Empty attaches no Firehose permissions to the task role."
  type        = string
  default     = ""
}

variable "data_pipeline_stream_name" {
  description = "firehose_stream_name output from the data stack"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Attach a WAF web ACL to the CloudFront distribution. Set false only where an SCP denies wafv2 at CloudFront scope."
  type        = bool
  default     = true
}
