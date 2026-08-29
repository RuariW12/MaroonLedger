# Used to scope catalog and log ARNs to this account and region.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
