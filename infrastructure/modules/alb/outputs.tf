output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.dns_name
}

output "target_group_arn" {
  description = "ARN of the ECS target group"
  value       = module.alb.target_groups["ecs"].arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix, the form CloudWatch expects as a dimension"
  value       = module.alb.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch dimensions"
  value       = module.alb.target_groups["ecs"].arn_suffix
}
