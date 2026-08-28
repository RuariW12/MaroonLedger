output "bucket_id" {
  description = "Name of the data lake bucket"
  value       = aws_s3_bucket.lake.id
}

output "bucket_arn" {
  description = "ARN of the data lake bucket"
  value       = aws_s3_bucket.lake.arn
}

output "raw_prefix" {
  description = "Prefix Firehose delivers into"
  value       = "raw/"
}

output "curated_prefix" {
  description = "Prefix the Glue job writes Parquet into"
  value       = "curated/"
}

output "raw_uri" {
  description = "s3:// URI of the raw zone"
  value       = "s3://${aws_s3_bucket.lake.id}/raw/"
}

output "curated_uri" {
  description = "s3:// URI of the curated zone"
  value       = "s3://${aws_s3_bucket.lake.id}/curated/"
}
