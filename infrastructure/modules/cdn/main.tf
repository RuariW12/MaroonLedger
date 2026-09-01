# Plain resources rather than terraform-aws-modules/s3-bucket.
#
# The community module was rejected by this Organization's SCP on
# CreateBucket, while an identical bucket created from a plain resource
# succeeds -- the module sends request parameters the policy refuses. Beyond
# unblocking that, this matches how the observability buckets are already
# written and makes the exact API call visible in the code.
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-frontend${var.bucket_suffix}"
  force_destroy = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The bucket is reached only through CloudFront's Origin Access Control, so
# ACLs have no role and are disabled outright.
resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.project_name}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  # Null rather than absent when disabled: CloudFront simply has no web ACL
  # attached, and every other behaviour of the distribution is unchanged.
  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # Once the ALB has its own certificate, the CloudFront-to-origin hop is
      # encrypted too, closing the last plaintext segment on the public path.
      origin_protocol_policy = var.alb_certificate_arn != "" ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      # Authorization must reach the origin or every API call is rejected.
      # Including it also keeps one user's responses out of another's cache.
      headers = ["Authorization", "Origin"]
      cookies {
        # Authentication is bearer-token based, so cookies are not part of the
        # request identity and only add cache-key entropy.
        forward = "none"
      }
    }

    # API responses must never be cached. Without these, CloudFront applies its
    # 24-hour default TTL: account balances would go stale, and a response
    # would still be served from the edge after the user signed out.
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # A custom domain requires a matching ACM certificate in us-east-1; without
  # one the distribution keeps its *.cloudfront.net name and default cert.
  aliases = var.domain_name != "" && var.acm_certificate_arn != "" ? [var.domain_name] : []

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""

    acm_certificate_arn = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method  = var.acm_certificate_arn != "" ? "sni-only" : null
    # Drops TLS 1.0/1.1 for viewers. Only applies with a custom certificate.
    minimum_protocol_version = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : null
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# Gated because some AWS Organizations deny wafv2 at CloudFront scope via SCP,
# and an SCP sits above IAM -- no amount of account permission overrides it.
# Defaults on, because a public distribution without a WAF is the wrong
# architecture; turning it off is a deliberate, environment-specific decision.
resource "aws_wafv2_web_acl" "main" {
  # A CLOUDFRONT-scoped ACL exists only in us-east-1, whatever region the rest
  # of the stack runs in.
  provider = aws.us_east_1

  count = var.enable_waf ? 1 : 0

  name  = "${var.project_name}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
    }
  }

  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
    }
  }

  rule {
    name     = "aws-managed-sql-injection"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli-rules"
    }
  }

  # Blocks request patterns that are never legitimate -- malformed headers,
  # path traversal, host-header injection.
  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-known-bad-inputs"
    }
  }

  # AWS-maintained list of sources associated with bots, scanners and botnets.
  # Cheap to evaluate and filters a large share of background noise.
  rule {
    name     = "aws-managed-ip-reputation"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-ip-reputation"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
