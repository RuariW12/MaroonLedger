output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}
