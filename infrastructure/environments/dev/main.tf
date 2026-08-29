module "vpc" {
  source             = "../../modules/vpc"
  project_name       = var.project_name
  single_nat_gateway = var.single_nat_gateway
}

module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
}

# Separate from the VPC module to avoid a dependency cycle: the endpoints need
# a security group, and the security groups need the VPC.
module "vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  source                  = "../../modules/vpc-endpoints"
  project_name            = var.project_name
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  vpce_security_group_id  = module.security_groups.vpce_security_group_id
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
  enable_password_rotation   = var.enable_password_rotation
}

# DNS and TLS. Inert until var.domain_name is set, which is what lets the
# stack apply without a registered domain.
module "dns" {
  source       = "../../modules/dns"
  project_name = var.project_name

  domain_name        = var.domain_name
  create_hosted_zone = var.create_hosted_zone

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "alb" {
  source                = "../../modules/alb"
  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id

  # Empty until a domain is configured, in which case the ALB serves HTTP only.
  certificate_arn = module.dns.alb_certificate_arn
}

module "cognito" {
  source                  = "../../modules/cognito"
  project_name            = var.project_name
  hosted_ui_domain_prefix = var.hosted_ui_domain_prefix
  advanced_security_mode  = var.cognito_advanced_security_mode

  # Once a domain exists, sign-in returns to it rather than to localhost.
  callback_urls = var.domain_name != "" ? concat(var.auth_callback_urls, ["https://${var.domain_name}/"]) : var.auth_callback_urls
  logout_urls   = var.domain_name != "" ? concat(var.auth_logout_urls, ["https://${var.domain_name}/"]) : var.auth_logout_urls
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

  db_host = module.rds.db_instance_endpoint
  db_port = module.rds.db_port
  db_name = module.rds.db_name

  ai_provider   = var.ai_provider
  bedrock_model = var.bedrock_model

  # Wired from the data stack's outputs, by hand rather than through
  # terraform_remote_state. Reading the other stack's state would couple them,
  # and coupling is exactly what must not exist if `terraform destroy` here is
  # to leave the lake untouched.
  data_pipeline             = var.data_pipeline
  data_pipeline_stream_arn  = var.data_pipeline_stream_arn
  data_pipeline_stream_name = var.data_pipeline_stream_name

  # Taken from the Cognito module's outputs rather than hand-assembled, so the
  # issuer the API validates against cannot drift from the pool that mints the
  # tokens.
  auth_issuer    = module.cognito.issuer
  auth_jwks_url  = module.cognito.jwks_url
  auth_client_id = module.cognito.client_id
}

module "cdn" {
  source       = "../../modules/cdn"
  project_name = var.project_name
  alb_dns_name = module.alb.alb_dns_name

  domain_name         = var.domain_name
  acm_certificate_arn = module.dns.edge_certificate_arn
  alb_certificate_arn = module.dns.alb_certificate_arn
  enable_waf          = var.enable_waf

  providers = {
    aws = aws.us_east_1
  }
}

module "observability" {
  source       = "../../modules/observability"
  project_name = var.project_name

  alert_email             = var.alert_email
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  db_instance_identifier  = module.rds.db_instance_identifier
}

module "ecr" {
  source       = "../../modules/ecr"
  project_name = var.project_name
}

# The apex alias lives here rather than inside the dns module to break a
# dependency cycle: CloudFront needs the certificate the dns module issues,
# so the dns module cannot in turn depend on CloudFront's outputs.
resource "aws_route53_record" "apex" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = module.dns.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name    = module.cdn.cloudfront_domain_name
    zone_id = module.cdn.cloudfront_hosted_zone_id
    # CloudFront is always healthy from Route 53's perspective, so target
    # health evaluation does not apply.
    evaluate_target_health = false
  }
}
