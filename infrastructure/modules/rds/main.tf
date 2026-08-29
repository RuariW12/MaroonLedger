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

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # RDS creates the master password, stores it in Secrets Manager, and rotates
  # it natively. This replaces a Terraform-generated random_password, which had
  # two problems: the password was written to state in plaintext, and rotating
  # it would otherwise require a Lambda in the VPC. Nothing here ever sees the
  # value.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  manage_master_user_password_rotation                   = var.enable_password_rotation
  master_user_password_rotate_immediately                = false
  master_user_password_rotation_automatically_after_days = var.password_rotation_days

  multi_az               = var.multi_az
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [var.rds_security_group_id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot

  # Postgres logs go to CloudWatch so they survive instance replacement and
  # are searchable alongside the application's own logs.
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
