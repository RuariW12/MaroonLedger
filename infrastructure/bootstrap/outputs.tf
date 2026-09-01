output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for every stack. Must match the bucket in each environment's backend.tf."
  value       = module.s3_bucket.s3_bucket_id
}

output "state_bucket_region" {
  description = "Region the state bucket lives in"
  value       = var.region
}
