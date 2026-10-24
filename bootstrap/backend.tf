terraform {
  backend "s3" {
    bucket       = "mhugley-ec2-demo-tfstate-283678155577-us-east-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
