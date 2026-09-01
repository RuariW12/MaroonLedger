# Kinesis Data Firehose, Direct PUT.
#
# Firehose rather than Kinesis Data Streams because Data Streams bills per
# shard-hour whether or not anything is written -- an idle floor of roughly
# $11/month per shard. Firehose Direct PUT bills per GB ingested and nothing
# when idle, which is the whole cost posture of this stack.
#
# NOTE ON PARTITIONING. The brief asked for "dynamic partitioning by ingest
# date". Firehose has two distinct mechanisms with the same colloquial name:
#
#   1. Timestamp namespace prefixes (!{timestamp:yyyy}/...) -- free, and
#      partitions by the time Firehose buffered the record.
#   2. The Dynamic Partitioning feature -- extracts keys from record content
#      with JQ, and adds a per-GB surcharge on top of ingestion plus a charge
#      per S3 object delivered.
#
# Ingest date is available without inspecting record content, so (2) would be
# paying a surcharge for something (1) does for nothing. Against a hard
# cost-optimality requirement that is the wrong trade, so this uses the
# timestamp namespace. If partitioning ever needs to key on a *field* --
# category, say -- that is when Dynamic Partitioning starts earning its cost.

resource "aws_kinesis_firehose_delivery_stream" "transactions" {
  name        = "${var.project_name}-transactions"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.lake_bucket_arn

    # 128 MB / 300s. Firehose delivers on whichever trips first, so this is a
    # ceiling on object count and PUT frequency, not a latency target: at this
    # application's volume the interval will always win, giving one object per
    # five minutes rather than thousands of tiny ones. Small objects are the
    # main way an S3 data lake becomes expensive to query.
    buffering_size     = var.buffer_size_mb
    buffering_interval = var.buffer_interval_seconds

    compression_format = "GZIP"

    prefix              = "raw/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "S3Delivery"
    }
  }

  # Firehose encrypts in transit to S3 and the bucket applies SSE-S3 at rest.
  # Server-side encryption on the stream itself is for Direct PUT payloads at
  # rest inside Firehose and requires KMS, which reintroduces per-request cost
  # for data that is already minimized.

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}

# Delivery failures are otherwise silent: Firehose retries toward S3 on its own
# and, if it exhausts them, writes to the error prefix without surfacing
# anything. This log group is where the reason appears. An empty log group
# costs nothing.
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}-transactions"
  retention_in_days = 14

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}

resource "aws_iam_role" "firehose" {
  name = "${var.project_name}-firehose-delivery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        # Without this a delivery-stream role is confused-deputy exposed: any
        # account able to name this role ARN could have their stream write into
        # our bucket.
        Condition = {
          StringEquals = {
            "sts:ExternalId" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.project_name}-firehose-delivery"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLandingZoneOnly"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        # Scoped to the two prefixes it delivers into. It cannot read or write
        # curated/, which is the Glue job's output and the thing Athena bills
        # against.
        Resource = [
          var.lake_bucket_arn,
          "${var.lake_bucket_arn}/raw/*",
          "${var.lake_bucket_arn}/errors/*",
        ]
      },
      {
        Sid      = "ListForMultipart"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.lake_bucket_arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["raw/*", "errors/*"]
          }
        }
      },
      {
        Sid      = "DeliveryLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.firehose.arn}:*"]
      },
    ]
  })
}
