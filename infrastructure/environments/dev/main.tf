module "vpc" {
  source       = "../../modules/vpc"
  project_name = var.project_name
}

module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
}

module "kms" {
  source       = "../../modules/kms"
  project_name = var.project_name
}

module "rds" {
  source                     = "../../modules/rds"
  project_name               = var.project_name
  database_subnet_group_name = module.vpc.database_subnet_group_name
  rds_security_group_id      = module.security_groups.rds_security_group_id
  kms_key_arn                = module.kms.kms_key_arn
}

module "alb" {
  source                = "../../modules/alb"
  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
}

module "ecs" {
  source                    = "../../modules/ecs"
  project_name              = var.project_name
  region                    = var.region
  container_image           = var.container_image
  private_subnet_ids        = module.vpc.private_subnet_ids
  ecs_security_group_id     = module.security_groups.ecs_security_group_id
  target_group_arn          = module.alb.target_group_arn
  db_credentials_secret_arn = module.rds.db_credentials_secret_arn
  kms_key_arn               = module.kms.kms_key_arn
}

module "cdn" {
  source       = "../../modules/cdn"
  project_name = var.project_name
  alb_dns_name = module.alb.alb_dns_name
}

module "observability" {
  source       = "../../modules/observability"
  project_name = var.project_name
}
