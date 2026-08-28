# Data stack.
#
# Everything here is serverless and bills on use, so it is safe to leave
# running while the compute stack is destroyed. That separation is the point:
# `terraform destroy` in environments/dev tears down the VPC, NAT, RDS and
# Fargate -- the parts with an hourly floor -- without touching the lake, the
# catalog or the delivery stream.
#
# The two stacks share no state. They are separate root modules with separate
# backend keys and no terraform_remote_state between them, so neither can plan
# a change to the other's resources.

module "datalake" {
  source       = "../../modules/datalake"
  project_name = var.project_name

  raw_retention_days    = var.raw_retention_days
  curated_ia_after_days = var.curated_ia_after_days
}

module "firehose" {
  source       = "../../modules/firehose"
  project_name = var.project_name

  lake_bucket_arn         = module.datalake.bucket_arn
  buffer_size_mb          = var.firehose_buffer_size_mb
  buffer_interval_seconds = var.firehose_buffer_interval_seconds
}

module "glue" {
  source       = "../../modules/glue"
  project_name = var.project_name

  lake_bucket_id  = module.datalake.bucket_id
  lake_bucket_arn = module.datalake.bucket_arn

  projection_start_date = var.projection_start_date
  schedule_expression   = var.etl_schedule_expression
  schedule_timezone     = var.etl_schedule_timezone
}

module "athena" {
  source       = "../../modules/athena"
  project_name = var.project_name

  scan_cutoff_bytes = var.athena_scan_cutoff_bytes
}

# A budget scoped to this stack's services rather than the whole account, so it
# reports what the pipeline costs independently of what the compute tier is
# doing. Budgets themselves are free.
#
# The threshold is deliberately low: at the volume this application produces,
# the expected monthly cost is a couple of dollars, so an alert at 20 USD means
# something has genuinely gone wrong -- a runaway Glue job, or a query loop --
# rather than gradual growth.
resource "aws_budgets_budget" "data_stack" {
  name         = "${var.project_name}-data-stack"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Filtered by service rather than by tag. Cost-allocation tags have to be
  # activated in Billing and then take up to 24 hours to appear, which makes a
  # tag-filtered budget silently empty on the day you create it.
  cost_filter {
    name = "Service"
    values = [
      "Amazon Kinesis Firehose",
      "AWS Glue",
      "Amazon Athena",
      "Amazon Simple Storage Service",
    ]
  }

  # Actual spend, so it fires on money already spent.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Forecast, so a spike is caught mid-month rather than after the bill.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}
