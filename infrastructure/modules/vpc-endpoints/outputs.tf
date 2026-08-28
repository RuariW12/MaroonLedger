output "interface_endpoint_ids" {
  description = "IDs of the interface endpoints, keyed by service"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}
