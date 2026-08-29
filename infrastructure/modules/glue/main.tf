# Glue PySpark ETL: raw JSON -> curated Parquet, plus the Data Catalog table
# Athena reads through.
#
# Glue bills per DPU-second while a job runs and nothing between runs, so a
# nightly job that finishes in a couple of minutes costs cents per month. No
# crawler: crawlers are a scheduled always-on-ish cost whose only job here
# would be discovering partitions that partition projection already describes
# deterministically.

resource "aws_s3_object" "etl_script" {
  bucket = var.lake_bucket_id
  key    = "scripts/transactions_etl.py"
  source = "${path.module}/etl/transactions_etl.py"

  # Without this the object is only replaced when the key changes, so edits to
  # the script would never reach the job.
  etag = filemd5("${path.module}/etl/transactions_etl.py")

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}

resource "aws_glue_catalog_database" "analytics" {
  name        = replace("${var.project_name}_analytics", "-", "_")
  description = "Curated analytics datasets for ${var.project_name}"
}

# The curated table, defined in Terraform with partition projection.
#
# Projection is what removes both the crawler and MSCK REPAIR TABLE: Athena
# computes the partition locations from the rules below instead of reading a
# partition list from the catalog. Nothing has to run to make a new day
# queryable -- the day exists in the projection the moment it exists in S3.
resource "aws_glue_catalog_table" "transactions" {
  name          = "transactions"
  database_name = aws_glue_catalog_database.analytics.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification        = "parquet"
    "parquet.compression" = "SNAPPY"
    EXTERNAL              = "TRUE"

    "projection.enabled" = "true"

    # Dates are projected from the first plausible event to whatever today is,
    # so the range never needs maintaining.
    "projection.event_date.type"          = "date"
    "projection.event_date.range"         = "${var.projection_start_date},NOW"
    "projection.event_date.format"        = "yyyy-MM-dd"
    "projection.event_date.interval"      = "1"
    "projection.event_date.interval.unit" = "DAYS"

    # An enum rather than injected: the category set is closed and defined in
    # internal/ai, so Athena can enumerate it. Injected would force every query
    # to name a category in its WHERE clause.
    "projection.category.type"   = "enum"
    "projection.category.values" = join(",", var.categories)

    "storage.location.template" = "s3://${var.lake_bucket_id}/curated/event_date=$${event_date}/category=$${category}"
  }

  storage_descriptor {
    location      = "s3://${var.lake_bucket_id}/curated/"
    input_format  = "org.apache.hadoop.mapred.FileInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "parquet"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    # Partition columns are deliberately absent: Hive-partitioned Parquet
    # encodes them in the object key, not in the file, so listing them here
    # would produce a duplicate-column error at query time.
    columns {
      name    = "id"
      type    = "bigint"
      comment = "Transaction primary key from the application database"
    }
    columns {
      name    = "event_ts"
      type    = "timestamp"
      comment = "When the transaction occurred (not when it was ingested)"
    }
    columns {
      name    = "amount"
      type    = "double"
      comment = "Signed amount; negative is money leaving the account"
    }
    columns {
      name    = "ai_provider"
      type    = "string"
      comment = "Which provider enriched the row: bedrock, stub, or none"
    }
    columns {
      name    = "anomaly_severity"
      type    = "string"
      comment = "none, low, medium or high"
    }
  }

  partition_keys {
    name    = "event_date"
    type    = "date"
    comment = "Date of the transaction, from event_ts"
  }
  partition_keys {
    name    = "category"
    type    = "string"
    comment = "Spending category, from the closed set in internal/ai"
  }
}

resource "aws_glue_job" "transactions_etl" {
  name     = "${var.project_name}-transactions-etl"
  role_arn = aws_iam_role.glue.arn

  glue_version = "4.0"

  # G.1X is the smallest worker Glue offers for Spark. Two of them is the
  # minimum the service accepts, and is far more than this data needs -- the
  # cost lever here is runtime, not width.
  worker_type       = "G.1X"
  number_of_workers = 2

  # A guard, not a target. A run that has not finished in 15 minutes at this
  # volume is stuck, and Glue bills until it is stopped.
  timeout = var.timeout_minutes

  # Fail fast: an ETL that retries a genuine data error just pays twice for the
  # same failure. The schedule will try again tomorrow.
  max_retries = 0

  command {
    name            = "glueetl"
    script_location = "s3://${var.lake_bucket_id}/${aws_s3_object.etl_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"

    "--raw_path"     = "s3://${var.lake_bucket_id}/raw/"
    "--curated_path" = "s3://${var.lake_bucket_id}/curated/"

    # The reason a nightly run never reprocesses: Glue persists which objects
    # it has consumed and skips them next time.
    "--job-bookmark-option" = "job-bookmark-enable"

    # Spark UI event logs and profiling both write to S3 continuously and are
    # debugging aids, not requirements. Off by default.
    "--enable-metrics"                   = "false"
    "--enable-spark-ui"                  = "false"
    "--enable-continuous-cloudwatch-log" = "false"

    "--TempDir" = "s3://${var.lake_bucket_id}/tmp/"
  }

  tags = {
    Terraform   = "true"
    Environment = "data"
  }
}
