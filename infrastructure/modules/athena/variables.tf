variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "scan_cutoff_bytes" {
  description = "Per-query scan ceiling. A query projected to exceed it is canceled before it runs. 1 GiB against a 5-USD-per-TB rate caps a single query at roughly half a cent."
  type        = number
  default     = 1073741824
}

variable "results_retention_days" {
  description = "Days before query results are deleted. They are regenerable by rerunning the query."
  type        = number
  default     = 30
}
