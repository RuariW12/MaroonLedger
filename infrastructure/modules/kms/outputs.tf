output "kms_key_arn" {
  description = "ARN of the KMS key for RDS encryption"
  value       = module.kms.key_arn
}
