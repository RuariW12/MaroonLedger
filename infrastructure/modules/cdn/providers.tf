terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Only the WAF web ACL genuinely requires us-east-1: a CLOUDFRONT-scoped
      # ACL can be created nowhere else. The distribution is a global resource
      # and the origin bucket should live with the rest of the stack, not in
      # another region -- putting it in us-east-1 while the application runs in
      # us-east-2 adds a cross-region hop and inter-region transfer cost on
      # every origin fetch.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
