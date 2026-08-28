variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "container_image" {
  description = "Docker image URI for the app container"
  type        = string
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
