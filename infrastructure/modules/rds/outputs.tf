output "db_instance_endpoint" {
  description = "RDS instance hostname (address only, no port)"
  value       = module.rds.db_instance_address
}

output "db_instance_identifier" {
  description = "RDS instance identifier, used for CloudWatch alarm dimensions"
  value       = module.rds.db_instance_identifier
}

output "db_port" {
  description = "Port the database listens on"
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Initial database name"
  value       = var.db_name
}

# The RDS-managed secret holds only username and password. Host, port and
# database name are not secret and are passed to the application as plain
# environment variables.
output "db_credentials_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials"
  value       = module.rds.db_instance_master_user_secret_arn
}
