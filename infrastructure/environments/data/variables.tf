variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "region" {
  description = "AWS region hosting the data stack. Should match the compute stack to avoid cross-region transfer charges on Firehose delivery."
  type        = string
  default     = "us-east-2"
}

# --- Retention -------------------------------------------------------------

variable "raw_retention_days" {
  description = "Days before raw/ objects expire"
  type        = number
  default     = 30
}

variable "curated_ia_after_days" {
  description = "Days before curated/ objects transition to Standard-IA"
  type        = number
  default     = 90
}

# --- Firehose --------------------------------------------------------------

variable "enable_firehose" {
  description = "Create the Firehose delivery stream. Set false where an SCP denies the service; the rest of the pipeline still deploys and raw/ is populated by direct S3 upload."
  type        = bool
  default     = true
}

variable "firehose_buffer_size_mb" {
  description = "Firehose buffer size in MB before delivery to S3"
  type        = number
  default     = 128
}

variable "firehose_buffer_interval_seconds" {
  description = "Maximum seconds a partial Firehose buffer waits before delivery"
  type        = number
  default     = 300
}

# --- ETL -------------------------------------------------------------------

variable "etl_schedule_expression" {
  description = "Schedule for the nightly Glue ETL"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "etl_schedule_timezone" {
  description = "Timezone the ETL schedule is evaluated in"
  type        = string
  default     = "UTC"
}

variable "projection_start_date" {
  description = "Earliest date Athena partition projection enumerates"
  type        = string
  default     = "2026-01-01"
}

# --- Athena ----------------------------------------------------------------

variable "athena_scan_cutoff_bytes" {
  description = "Per-query scan ceiling in bytes. Defaults to 1 GiB."
  type        = number
  default     = 1073741824
}

# --- Cost ------------------------------------------------------------------

variable "monthly_budget_usd" {
  description = "Monthly budget for the data stack's services"
  type        = string
  default     = "20"
}

variable "budget_alert_emails" {
  description = "Addresses notified when the data-stack budget is breached. Empty creates the budget with no subscriber."
  type        = list(string)
  default     = []
}
