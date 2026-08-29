
variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "single_nat_gateway" {
  description = "Share one NAT Gateway across both AZs. Cheaper, but a single point of failure and a cross-AZ data charge. Set false for production."
  type        = bool
  default     = true
}

