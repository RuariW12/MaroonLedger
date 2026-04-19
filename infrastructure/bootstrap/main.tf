# Define s3 bucket for remote state backend
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "${var.project_name}-terraform-state"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  tags = {
    Terraform = "true"
    Purpose   = "terraform-state"
  }
}

# Define dynamodb table for state locking
module "dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 4.0"

  name     = "${var.project_name}-terraform-lock"
  hash_key = "LockID"

  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    {
      name = "LockID"
      type = "S"
    }
  ]

  tags = {
    Terraform = "true"
    Purpose   = "terraform-state-lock"
  }
}
