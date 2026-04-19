output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = module.s3_bucket.s3_bucket_id
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = module.dynamodb_table.dynamodb_table_id
}
