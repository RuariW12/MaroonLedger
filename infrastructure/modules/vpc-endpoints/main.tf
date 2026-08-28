# VPC Endpoints keep AWS API traffic inside the VPC instead of routing it out
# through the NAT Gateway. Three reasons, in order of how much they matter here:
# secret retrieval and image pulls never touch the public internet; NAT data
# processing charges disappear for this traffic; and the tasks keep working if
# the NAT Gateway or its AZ fails.
#
# Interface endpoints are billed hourly per endpoint per AZ, so only the
# services the tasks actually call are created.

data "aws_region" "current" {}

locals {
  interface_endpoints = {
    # Pulling the container image needs both: ecr.api authenticates, ecr.dkr
    # serves the layers.
    ecr_api = "ecr.api"
    ecr_dkr = "ecr.dkr"
    # The awslogs driver ships container output here.
    logs = "logs"
    # The task fetches DB_CREDENTIALS from here at startup.
    secretsmanager = "secretsmanager"
    # ECS Exec, for shelling into a running task to debug.
    ssm         = "ssm"
    ssmmessages = "ssmmessages"
    # Model inference for the AI features.
    bedrock_runtime = "bedrock-runtime"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpce_security_group_id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-${each.key}-endpoint"
    Terraform   = "true"
    Environment = "dev"
  }
}

# S3 is a Gateway endpoint: it attaches to route tables rather than creating
# ENIs, and unlike interface endpoints it costs nothing. ECR stores image
# layers in S3, so this is required for image pulls to work without NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    Terraform   = "true"
    Environment = "dev"
  }
}
