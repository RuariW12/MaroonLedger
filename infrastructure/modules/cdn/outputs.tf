output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "frontend_bucket_name" {
  description = "S3 bucket name for frontend deployment"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront's fixed hosted zone ID, used for Route 53 alias records"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}
