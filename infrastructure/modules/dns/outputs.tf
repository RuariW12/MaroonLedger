output "zone_id" {
  description = "Route 53 hosted zone ID, empty when the DNS layer is disabled"
  value       = local.zone_id
}

output "name_servers" {
  description = "Name servers to set at the registrar. Only populated when this module creates the zone."
  value       = try(aws_route53_zone.main[0].name_servers, [])
}

# Consumers gate on these being non-empty rather than on domain_name, so the
# ALB and CloudFront need no knowledge of how the DNS layer is configured.
output "edge_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  value       = try(aws_acm_certificate_validation.edge[0].certificate_arn, "")
}

output "alb_certificate_arn" {
  description = "ACM certificate ARN in the app region for the ALB"
  value       = try(aws_acm_certificate_validation.alb[0].certificate_arn, "")
}

output "domain_name" {
  description = "Configured domain name, empty when disabled"
  value       = var.domain_name
}
