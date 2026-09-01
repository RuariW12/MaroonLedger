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

variable "enable_alarms" {
  description = "Create the service health alarms. Must be statically known: gating on whether a dimension is empty makes count depend on an apply-time value, which Terraform rejects."
  type        = bool
  default     = true
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

variable "enable_guardduty" {
  description = "Create a GuardDuty detector. Set false where an SCP denies the service or the Organization runs detection centrally."
  type        = bool
  default     = true
}

variable "bucket_suffix" {
  description = "Suffix for the CloudTrail and Config log buckets. S3 names are global, so a bare project name collides with any account that used it before."
  type        = string
  default     = ""
}
