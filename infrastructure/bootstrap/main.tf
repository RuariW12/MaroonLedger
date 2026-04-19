module "bootstrap" {
  source = "trussworks/bootstrap/aws"

  region        = "us-west-2"
  account_alias = "<ORG>-<NAME>"
}
