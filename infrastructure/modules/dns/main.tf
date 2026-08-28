# DNS and TLS certificates.
#
# The entire module is inert until var.domain_name is set, so the stack applies
# cleanly without a registered domain and gains DNS + TLS by setting one
# variable. Everything here is free except the hosted zone ($0.50/month).
#
# Two certificates are needed because they live in different places:
#   - the CloudFront certificate MUST be in us-east-1, whatever region the rest
#     of the stack runs in (a CloudFront constraint, not a choice)
#   - the ALB certificate must be in the ALB's own region
# They cover the same name and validate through the same hosted zone.

locals {
  enabled = var.domain_name != ""

  # A zone is either created here or looked up. Referencing whichever exists
  # keeps every downstream record identical in both cases.
  zone_id = local.enabled ? (
    var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  ) : ""
}

resource "aws_route53_zone" "main" {
  count = local.enabled && var.create_hosted_zone ? 1 : 0

  name = var.domain_name

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Used when the domain is registered elsewhere and its zone already exists.
data "aws_route53_zone" "existing" {
  count = local.enabled && !var.create_hosted_zone ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

# --- Edge certificate (CloudFront, must be us-east-1) ---

resource "aws_acm_certificate" "edge" {
  count    = local.enabled ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  # The replacement certificate is issued and validated before the old one is
  # removed, so a renewal never leaves the distribution without a certificate.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-edge"
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_route53_record" "edge_validation" {
  for_each = local.enabled ? {
    for option in aws_acm_certificate.edge[0].domain_validation_options :
    option.domain_name => option
  } : {}

  zone_id = local.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60

  # ACM reuses a validation record when a name appears more than once, so
  # overwrite rather than fail on an existing record.
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "edge" {
  count    = local.enabled ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.edge[0].arn
  validation_record_fqdns = [for record in aws_route53_record.edge_validation : record.fqdn]
}

# --- Regional certificate (ALB) ---

resource "aws_acm_certificate" "alb" {
  count = local.enabled ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-alb"
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_route53_record" "alb_validation" {
  for_each = local.enabled ? {
    for option in aws_acm_certificate.alb[0].domain_validation_options :
    option.domain_name => option
  } : {}

  zone_id         = local.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "alb" {
  count = local.enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.alb_validation : record.fqdn]
}
