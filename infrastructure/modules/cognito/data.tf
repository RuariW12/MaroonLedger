# The issuer and JWKS URLs are region-scoped, so the region is read from the
# provider rather than passed in and risking a mismatch.
data "aws_region" "current" {}
