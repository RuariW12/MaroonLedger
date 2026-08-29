output "database_name" {
  description = "Glue Data Catalog database holding the curated table"
  value       = aws_glue_catalog_database.analytics.name
}

output "table_name" {
  description = "Curated transactions table, queryable from Athena"
  value       = aws_glue_catalog_table.transactions.name
}

output "job_name" {
  description = "Name of the Glue ETL job"
  value       = aws_glue_job.transactions_etl.name
}

output "job_arn" {
  description = "ARN of the Glue ETL job"
  value       = aws_glue_job.transactions_etl.arn
}

output "schedule_name" {
  description = "EventBridge Scheduler schedule that triggers the job"
  value       = aws_scheduler_schedule.nightly_etl.name
}
