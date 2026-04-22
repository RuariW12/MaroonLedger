terraform {
  backend "s3" {
    bucket         = "maroon-ledger-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "maroon-ledger-terraform-lock"
    encrypt        = true
  }
}
