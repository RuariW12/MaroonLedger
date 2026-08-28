# Separate state key from the compute stack.
#
# This is what makes `terraform destroy` in environments/dev incapable of
# touching the lake: the two root modules address different state objects, so
# the compute stack has no record of these resources to destroy.
terraform {
  backend "s3" {
    bucket         = "maroon-ledger-terraform-state"
    key            = "data/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "maroon-ledger-terraform-lock"
    encrypt        = true
  }
}
