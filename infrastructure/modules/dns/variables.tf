variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "domain_name" {
  description = "Domain for the application, e.g. maroonledger.com. Empty disables the entire DNS and TLS layer."
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "Create the Route 53 hosted zone. Set false if the zone already exists (domain registered elsewhere)."
  type        = bool
  default     = true
}
