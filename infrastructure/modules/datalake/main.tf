# One bucket, two prefixes.
#
# raw/     newline-delimited gzipped JSON, exactly as Firehose delivered it
# curated/ Snappy Parquet, partitioned by event_date and category
#
# Separate buckets would buy nothing here -- the access boundary that matters
# is between the Firehose role (writes raw/ only) and the Glue role (reads
# raw/, writes curated/), and that is expressed in their IAM policies rather
# than in bucket names.
#
# Storage is the only thing in this stack that bills while idle, and it bills
# per byte stored with no floor: an empty bucket costs nothing.

resource "aws_s3_bucket" "lake" {
  bucket = "${var.project_name}-datalake"

  # The lake is derivable: raw/ is a copy of rows that live in RDS, and
  # curated/ is recomputed from raw/. Nothing here is a system of record, so
  # tearing it down is recoverable.
  force_destroy = var.force_destroy

  tags = {
    Terraform   = "true"
    Environment = "data"
    Purpose     = "analytics-datalake"
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket = aws_s3_bucket.lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 rather than the customer-managed KMS key the RDS tier uses. KMS bills
# per request, and a Glue job rewriting a day of partitions issues a decrypt
# per object -- real money for data that is already a lower-sensitivity
# derivative (no descriptions, no account identifiers). Encryption at rest is
# still mandatory, which is what SSE-S3 provides at no cost.
resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Versioning stays off deliberately. Every object here is either replayable
# from Firehose or recomputable by the Glue job, so versions would only
# accumulate storage cost against data that is already reproducible.
resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  # Raw is a landing zone, not an archive. Once the ETL has folded a day into
  # curated/, the JSON has served its purpose; keeping 30 days leaves room to
  # reprocess after a bad job run without paying to store it indefinitely.
  rule {
    id     = "expire-raw"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = var.raw_retention_days
    }

    # Firehose retries can leave partial uploads behind; without this they are
    # billed as storage forever and are invisible in the console.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Curated is queried often when recent and rarely once it ages. Standard-IA
  # is roughly 45% cheaper per byte, against a per-GB retrieval fee that only
  # applies to the older partitions Athena seldom scans.
  rule {
    id     = "curated-to-ia"
    status = "Enabled"

    filter {
      prefix = "curated/"
    }

    transition {
      days          = var.curated_ia_after_days
      storage_class = "STANDARD_IA"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
