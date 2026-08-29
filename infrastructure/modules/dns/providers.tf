terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # CloudFront certificates must live in us-east-1 regardless of where the
      # rest of the stack runs, so this module needs both the default provider
      # and an explicitly-passed us-east-1 alias.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
