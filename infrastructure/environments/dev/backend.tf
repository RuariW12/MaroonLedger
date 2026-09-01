# Remote state.
#
# Each stack has its own key in one bucket. Separate keys are what make the
# stacks independently destroyable: `terraform destroy` in one root module
# addresses a different state object and has no record of the other's
# resources.
#
# Locking is native S3 (a lock file beside the state object), not DynamoDB.
# Terraform 1.10+ supports it and deprecates the `dynamodb_table` argument, so
# there is no lock table to provision or pay for.
terraform {
  backend "s3" {
    bucket       = "maroon-ledger-tfstate-4cc78b"
    key          = "dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
