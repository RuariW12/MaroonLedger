output "cloudfront_domain_name" {
  description = "URL to access the application"
  value       = module.cdn.cloudfront_domain_name
}

output "alb_dns_name" {
  description = "ALB DNS name for direct API access"
  value       = module.alb.alb_dns_name
}

output "db_instance_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_instance_endpoint
}

output "frontend_bucket_name" {
  description = "S3 bucket for frontend deployment"
  value       = module.cdn.frontend_bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing images"
  value       = module.ecr.repository_url
}
