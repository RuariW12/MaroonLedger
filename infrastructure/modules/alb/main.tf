module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false

  vpc_id  = var.vpc_id
  subnets = var.public_subnet_ids

  security_groups = [var.alb_security_group_id]
  create_security_group = false

  enable_deletion_protection = false

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs"
      }
    }
  }

  target_groups = {
    ecs = {
      name             = "${var.project_name}-ecs-tg"
      protocol         = "HTTP"
      port             = 3000
      target_type      = "ip"
      create_attachment = false

      health_check = {
        enabled             = true
        path                = "/health"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        timeout             = 5
      }
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
