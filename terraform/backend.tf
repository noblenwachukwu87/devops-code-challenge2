terraform {
  backend "s3" {
    bucket       = "devops-code-challenge2-tfstate-491865087343"
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}