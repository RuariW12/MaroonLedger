module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs              = ["us-east-2a", "us-east-2b"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24"]

  enable_nat_gateway = true

  # One NAT Gateway is roughly $32/month, so a second is the single largest
  # avoidable cost in this stack. Sharing one means an AZ failure takes out
  # outbound traffic for both private subnets and adds a cross-AZ data charge;
  # that is an acceptable trade for a portfolio environment and the wrong one
  # for production, hence the variable rather than a hardcoded choice.
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  # The database tier gets its own route table with no 0.0.0.0/0 entry. Subnet
  # names are only labels -- the absence of a default route is what actually
  # isolates the tier.
  create_database_subnet_route_table = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
