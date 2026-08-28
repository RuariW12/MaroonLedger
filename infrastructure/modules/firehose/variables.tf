variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "lake_bucket_arn" {
  description = "ARN of the data lake bucket Firehose delivers into"
  type        = string
}

variable "buffer_size_mb" {
  description = "Buffer size before delivery. Larger means fewer, bigger S3 objects, which is what keeps the lake cheap to query."
  type        = number
  default     = 128
}

variable "buffer_interval_seconds" {
  description = "Maximum time a partial buffer waits before delivery"
  type        = number
  default     = 300
}
