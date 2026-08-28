# Listener configuration.
#
# With a certificate the ALB terminates TLS on 443 and port 80 only redirects.
# Without one (no domain configured yet) it serves plain HTTP, which is why the
# security group restricts the ALB to CloudFront's edge ranges either way.
#
# Each listener is built by a `for` over a conditional *list* rather than a
# conditional over maps. Terraform type-checks both arms of a conditional and
# refuses to unify object types with different attributes -- so both
# `cond ? {https=...} : {http=...}` and `cond ? {https=...} : {}` are rejected,
# because a redirect listener and a forward listener have different shapes.
# Conditioning on `[]` vs `["name"]` compares two lists of strings, which
# unifies trivially, and each comprehension yields one homogeneous map that
# merge() then combines.

locals {
  tls_enabled = var.certificate_arn != ""

  https_listener = {
    for name in(local.tls_enabled ? ["https"] : []) : name => {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.certificate_arn
      # TLS 1.2 is the floor; this policy also enables 1.3. Anything still
      # permitting TLS 1.0/1.1 fails a PCI or SOC 2 review.
      ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

      forward = {
        target_group_key = "ecs"
      }
    }
  }

  http_redirect_listener = {
    for name in(local.tls_enabled ? ["http_redirect"] : []) : name => {
      port     = 80
      protocol = "HTTP"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  http_listener = {
    for name in(local.tls_enabled ? [] : ["http"]) : name => {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs"
      }
    }
  }

  listeners = merge(local.https_listener, local.http_redirect_listener, local.http_listener)
}
