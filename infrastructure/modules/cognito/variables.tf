variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "hosted_ui_domain_prefix" {
  description = "Globally unique prefix for the Cognito hosted UI domain"
  type        = string
}

variable "callback_urls" {
  description = "URLs Cognito may redirect to after a successful sign-in"
  type        = list(string)
  default     = ["http://localhost:3001/"]
}

variable "logout_urls" {
  description = "URLs Cognito may redirect to after sign-out"
  type        = list(string)
  default     = ["http://localhost:3001/"]
}

variable "advanced_security_mode" {
  description = "Cognito threat protection: OFF, AUDIT, or ENFORCED. AUDIT and ENFORCED are billed per monthly active user."
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be one of: OFF, AUDIT, ENFORCED."
  }
}
