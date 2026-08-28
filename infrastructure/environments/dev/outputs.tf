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

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito app client ID for the frontend"
  value       = module.cognito.client_id
}

output "cognito_hosted_ui_url" {
  description = "Cognito hosted sign-in URL"
  value       = module.cognito.hosted_ui_url
}

output "cognito_issuer" {
  description = "OIDC issuer the API validates tokens against"
  value       = module.cognito.issuer
}

output "alerts_topic_arn" {
  description = "SNS topic receiving GuardDuty findings and CloudWatch alarms"
  value       = module.observability.alerts_topic_arn
}

output "route53_name_servers" {
  description = "Name servers to set at the registrar. Only populated when Terraform creates the hosted zone."
  value       = module.dns.name_servers
}

output "application_url" {
  description = "Public URL of the application"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.cdn.cloudfront_domain_name}"
}
