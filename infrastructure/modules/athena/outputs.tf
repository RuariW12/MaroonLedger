output "workgroup_name" {
  description = "Athena workgroup to run curated-data queries in"
  value       = aws_athena_workgroup.analytics.name
}

output "results_bucket" {
  description = "Bucket holding Athena query results"
  value       = aws_s3_bucket.results.id
}

output "results_bucket_arn" {
  description = "ARN of the results bucket, for workgroup-scoped IAM"
  value       = aws_s3_bucket.results.arn
}
