terraform_binary = "terraform"
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "mhugley-ec2-demo-tfstate-283678155577-us-east-1"
    key          = "dev/ec2/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
  disable_init = true
}
