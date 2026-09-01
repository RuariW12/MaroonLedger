variable "project_name" {
  description = "Project name used to prefix resource names"
  type        = string
  default     = "maroon-ledger"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "container_image" {
  description = "Docker image URI for the app container"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN for the ECS service"
  type        = string
}

variable "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret for DB credentials"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for decrypting secrets"
  type        = string
}

variable "ai_provider" {
  description = "Which AI backend the application uses: 'bedrock' or 'stub'. Bedrock IAM permissions are only attached when this is 'bedrock'."
  type        = string
  default     = "bedrock"

  validation {
    condition     = contains(["bedrock", "stub"], var.ai_provider)
    error_message = "ai_provider must be either 'bedrock' or 'stub'."
  }
}

variable "bedrock_model" {
  description = "Bedrock model ID. Empty uses the application default."
  type        = string
  default     = ""
}

variable "auth_issuer" {
  description = "Expected OIDC issuer (the token's iss claim)"
  type        = string
}

variable "auth_jwks_url" {
  description = "JWKS endpoint used to verify token signatures"
  type        = string
}

variable "auth_client_id" {
  description = "Cognito app client ID the token's client_id claim must match"
  type        = string
}

variable "db_host" {
  description = "RDS hostname (address only, no port)"
  type        = string
}

variable "db_port" {
  description = "RDS port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "maroonledger"
}

variable "data_pipeline" {
  description = "Analytics emitter mode: 'off' or 'firehose'. Off by default so the pipeline can never start billing by accident."
  type        = string
  default     = "off"

  validation {
    condition     = contains(["off", "firehose"], var.data_pipeline)
    error_message = "data_pipeline must be either 'off' or 'firehose'."
  }
}

variable "data_pipeline_stream_arn" {
  description = "ARN of the Firehose delivery stream from the data stack. Empty attaches no Firehose permissions."
  type        = string
  default     = ""
}

variable "data_pipeline_stream_name" {
  description = "Name of the Firehose delivery stream the application publishes to"
  type        = string
  default     = ""
}

variable "bedrock_api" {
  description = "Bedrock surface: 'mantle' (newer Anthropic-operated Messages endpoint) or 'runtime' (classic bedrock-runtime). Mantle is not available to every account and answers 404 for every model where it is not."
  type        = string
  default     = "mantle"
}
