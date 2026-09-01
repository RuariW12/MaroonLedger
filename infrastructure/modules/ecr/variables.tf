variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "image_tag_mutability" {
  description = <<-EOT
    MUTABLE allows pushing a different image under an existing tag, which is
    what a manual `docker push :latest` relies on and what the ECS module's
    default container_image expects.

    Once CI owns deployments the stronger setting is IMMUTABLE: the pipeline
    tags by commit SHA, so a tag should never be reused, and immutability makes
    a rewritten history impossible to deploy silently. Switching requires the
    task definition to reference the SHA tag rather than :latest.
  EOT
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
