variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC the endpoints are created in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private-app subnets that receive an endpoint ENI"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Route tables the S3 gateway endpoint attaches to"
  type        = list(string)
}

variable "vpce_security_group_id" {
  description = "Security group controlling access to the interface endpoints"
  type        = string
}
