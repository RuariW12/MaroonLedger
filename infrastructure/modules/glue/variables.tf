variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "lake_bucket_id" {
  description = "Name of the data lake bucket"
  type        = string
}

variable "lake_bucket_arn" {
  description = "ARN of the data lake bucket"
  type        = string
}

variable "categories" {
  description = "Closed set of spending categories, mirroring internal/ai. Athena projects partitions from exactly this list, so a category missing here is invisible to queries."
  type        = list(string)
  default = [
    "groceries", "dining", "transport", "housing", "utilities", "healthcare",
    "entertainment", "shopping", "income", "transfer", "fees", "other",
  ]
}

variable "projection_start_date" {
  description = "Earliest date partition projection enumerates. Earlier than the first event, but not so early that Athena projects thousands of empty partitions."
  type        = string
  default     = "2026-01-01"
}

variable "timeout_minutes" {
  description = "Kill the job after this long. A guard against paying for a stuck run, not a performance target."
  type        = number
  default     = 15
}

variable "schedule_expression" {
  description = "When the ETL runs. Nightly by default."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone the schedule expression is evaluated in"
  type        = string
  default     = "UTC"
}
