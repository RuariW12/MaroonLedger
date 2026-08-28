output "stream_name" {
  description = "Name of the delivery stream the application writes to"
  value       = aws_kinesis_firehose_delivery_stream.transactions.name
}

output "stream_arn" {
  description = "ARN of the delivery stream. The compute stack scopes the ECS task role's firehose:PutRecord* to exactly this."
  value       = aws_kinesis_firehose_delivery_stream.transactions.arn
}
