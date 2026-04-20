module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 3.0"

  description = "KMS key for RDS encryption"
  key_usage   = "ENCRYPT_DECRYPT"

  enable_key_rotation = true

  aliases = ["${var.project_name}-rds"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
