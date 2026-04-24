resource "random_password" "db_password" {
  length  = 32
  special = false
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project_name}-db"

  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "maroonledger"
  username = "dbadmin"
  password = random_password.db_password.result
  port     = 5432

  manage_master_user_password = false

  multi_az               = true
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [var.rds_security_group_id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials"
  description = "RDS credentials for ${var.project_name}"
  kms_key_id  = var.kms_key_arn
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_password.result
    host     = module.rds.db_instance_endpoint
    port     = 5432
    dbname   = "maroonledger"
  })
}
