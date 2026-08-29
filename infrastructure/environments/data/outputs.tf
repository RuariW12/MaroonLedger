output "firehose_stream_name" {
  description = "Set as DATA_PIPELINE_STREAM on the application"
  value       = module.firehose.stream_name
}

output "firehose_stream_arn" {
  description = "Pass to the compute stack as data_pipeline_stream_arn so the ECS task role can write to exactly this stream"
  value       = module.firehose.stream_arn
}

output "datalake_bucket" {
  description = "Data lake bucket name"
  value       = module.datalake.bucket_id
}

output "raw_uri" {
  description = "s3:// URI Firehose delivers into"
  value       = module.datalake.raw_uri
}

output "curated_uri" {
  description = "s3:// URI the Glue job writes Parquet into"
  value       = module.datalake.curated_uri
}

output "glue_job_name" {
  description = "Glue ETL job name, for a manual run"
  value       = module.glue.job_name
}

output "athena_workgroup" {
  description = "Athena workgroup to query in"
  value       = module.athena.workgroup_name
}

output "athena_table" {
  description = "Fully qualified curated table"
  value       = "${module.glue.database_name}.${module.glue.table_name}"
}

output "sample_query" {
  description = "A partition-pruned query to verify the pipeline end to end"
  value       = <<-SQL
    SELECT category, count(*) AS txns, round(sum(amount), 2) AS net
    FROM ${module.glue.database_name}.${module.glue.table_name}
    WHERE event_date >= current_date - interval '30' day
    GROUP BY category
    ORDER BY abs(sum(amount)) DESC;
  SQL
}
