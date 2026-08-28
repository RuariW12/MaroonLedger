variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "alert_email" {
  description = "Address subscribed to the alerts topic. Empty creates the topic with no subscription; the subscription must be confirmed from the inbox."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions. Empty skips the ALB alarms."
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch dimensions"
  type        = string
  default     = ""
}

variable "db_instance_identifier" {
  description = "RDS instance identifier for CloudWatch dimensions. Empty skips the RDS alarms."
  type        = string
  default     = ""
}
