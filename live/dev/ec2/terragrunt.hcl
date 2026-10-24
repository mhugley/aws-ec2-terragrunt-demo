include "root" {
  path = find_in_parent_folders("root.hcl")
}
terraform {
  source = "../../../modules//ec2"
}
inputs = {
  region        = "us-east-1"
  vpc_id        = "vpc-0b57a3944dfc414b6"
  subnet_id     = "subnet-06218381657578b32"
  ami_id        = "ami-07890d146f8d6ee5b"
  instance_type = "t4g.micro"
}
