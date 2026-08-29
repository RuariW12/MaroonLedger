variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "raw_retention_days" {
  description = "Days before raw/ objects expire. Long enough to reprocess after a bad ETL run, short enough not to pay to archive JSON."
  type        = number
  default     = 30
}

variable "curated_ia_after_days" {
  description = "Days before curated/ objects move to Standard-IA"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed with objects in it. Safe here because every object is replayable or recomputable."
  type        = bool
  default     = true
}
