resource "aws_iam_role" "glue" {
  name = "${var.project_name}-glue-etl"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}

# Deliberately not AWSGlueServiceRole, the managed policy every tutorial
# attaches. That policy grants s3:* on any bucket whose name contains
# "aws-glue-", plus broad catalog access across the account. This job touches
# one bucket and one database, so the policy says so.
resource "aws_iam_role_policy" "glue" {
  name = "${var.project_name}-glue-etl"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLandingZoneAndScript"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.lake_bucket_arn}/raw/*",
          "${var.lake_bucket_arn}/scripts/*",
        ]
      },
      {
        Sid    = "WriteCuratedAndTemp"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
        ]
        # No write access to raw/. The job's input is immutable to it, so a bug
        # in the ETL cannot destroy the landing zone it would need in order to
        # recover.
        Resource = [
          "${var.lake_bucket_arn}/curated/*",
          "${var.lake_bucket_arn}/tmp/*",
        ]
      },
      {
        Sid      = "ListForSparkPathResolution"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.lake_bucket_arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["raw/*", "curated/*", "scripts/*", "tmp/*"]
          }
        }
      },
      {
        Sid    = "CatalogForThisDatabaseOnly"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:CreatePartition",
          "glue:UpdatePartition",
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.analytics.name}",
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.analytics.name}/*",
        ]
      },
      {
        Sid    = "JobLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
      },
    ]
  })
}

# --- Nightly trigger -------------------------------------------------------

# EventBridge Scheduler rather than a container running cron. Scheduler is
# serverless and bills per invocation -- 30 invocations a month is free-tier
# noise -- where a cron container is an always-on task paying for 24 hours to
# do two minutes of work.
resource "aws_scheduler_schedule" "nightly_etl" {
  name        = "${var.project_name}-transactions-etl-nightly"
  description = "Fold the previous day's raw transactions into curated Parquet"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  # Scheduler spreads invocations across the window rather than firing every
  # schedule in the account at exactly the same second. Nothing downstream
  # cares when overnight this runs.
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 15
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:glue:startJobRun"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      JobName = aws_glue_job.transactions_etl.name
    })

    retry_policy {
      # One retry covers a transient Glue throttle. Beyond that the schedule
      # fires again tomorrow, and bookmarks mean nothing is lost by waiting.
      maximum_retry_attempts = 1
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-glue-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
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

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project_name}-glue-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["glue:StartJobRun"]
        # This one job. The scheduler cannot start anything else in the
        # account, which is the difference between a trigger and a foothold.
        Resource = [aws_glue_job.transactions_etl.arn]
      }
    ]
  })
}
