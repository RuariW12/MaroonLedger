# Athena workgroup with a hard scan cap.
#
# Athena bills $5 per TB scanned and nothing at rest, so an idle workgroup is
# free. The risk is not idle cost, it is a single careless query: SELECT *
# without a partition predicate against a large table is one command that can
# cost real money. The cutoff below makes that fail instead.

resource "aws_s3_bucket" "results" {
  bucket = "${var.project_name}-athena-results"

  # Query results are disposable by definition -- rerunning the query
  # regenerates them.
  force_destroy = true

  tags = {
    Terraform   = "true"
    Environment = "data"
    Purpose     = "athena-query-results"
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Results accumulate silently -- every query writes one, nobody deletes them,
# and they are the most common source of surprise S3 growth on an otherwise
# tidy account.
resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = var.results_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

resource "aws_athena_workgroup" "analytics" {
  name        = "${var.project_name}-analytics"
  description = "Curated transaction analytics for ${var.project_name}"

  configuration {
    # Without this a user can override the results location and the scan cap
    # from their client, which makes both settings advisory rather than
    # enforced.
    enforce_workgroup_configuration = true

    # The guardrail. A query projected to scan more than this is cancelled
    # before it runs, so the ceiling on a single mistake is bounded rather
    # than open-ended.
    bytes_scanned_cutoff_per_query = var.scan_cutoff_bytes

    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.id}/output/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  # Deleting a workgroup with query history normally fails; this is a portfolio
  # environment that gets torn down.
  force_destroy = true

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}
