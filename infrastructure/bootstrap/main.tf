# Remote state backend.
#
# This root module bootstraps the bucket that every other stack stores its
# state in, which is why it is the one module that keeps its state on disk:
# it cannot use a backend that does not exist yet.
#
# There is no DynamoDB lock table. Terraform 1.10 added native S3 state
# locking via a lock file held in the same bucket, and `dynamodb_table` on the
# S3 backend is deprecated in favor of it. Dropping the table removes a
# resource, a module dependency, and the IAM surface that went with it.

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = var.state_bucket_name

  # State is the one thing here that is genuinely irreplaceable -- lose it and
  # Terraform no longer knows what it manages. Versioning is what makes a bad
  # apply or a corrupted write recoverable.
  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
      # Cuts KMS request charges by caching a data key per object prefix.
      bucket_key_enabled = true
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # State files hold resource metadata and can hold secrets. Nothing should
  # ever reach this bucket unencrypted or over plain HTTP.
  attach_deny_insecure_transport_policy = true

  # Old state versions accumulate silently; ninety days is enough history to
  # recover from a bad apply without paying to keep every write forever.
  lifecycle_rule = [
    {
      id      = "expire-old-state-versions"
      enabled = true

      noncurrent_version_expiration = {
        days = 90
      }

      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = {
    Terraform = "true"
    Purpose   = "terraform-state"
  }
}
