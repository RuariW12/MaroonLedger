variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "container_image" {
  description = "Docker image URI for the app container"
  type        = string
}
