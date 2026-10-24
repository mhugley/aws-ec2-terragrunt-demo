provider "aws" {
  region              = var.region
  allowed_account_ids = ["283678155577"]
  default_tags {
    tags = {
      Project     = "ec2-terragrunt-demo"
      Environment = "dev"
      ManagedBy   = "Terraform"
      Repository  = "mhugley/aws-ec2-terragrunt-demo"
    }
  }
}
data "aws_subnet" "existing" {
  id = var.subnet_id
}
data "aws_ami" "selected" {
  owners = ["amazon"]
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}
resource "aws_security_group" "instance" {
  name_prefix = "ec2-terragrunt-demo-"
  description = "Isolated demo instance: no inbound or outbound network rules"
  vpc_id      = var.vpc_id
  ingress     = []
  egress      = []
  tags        = { Name = "ec2-terragrunt-demo" }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_instance" "demo" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = false
  monitoring                  = false
  ebs_optimized               = true
  user_data_replace_on_change = true
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    tags = {
      Name        = "ec2-terragrunt-demo-root"
      Project     = "ec2-terragrunt-demo"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
  tags = { Name = "ec2-terragrunt-demo" }
  lifecycle {
    precondition {
      condition     = data.aws_subnet.existing.vpc_id == var.vpc_id
      error_message = "The subnet must belong to the selected existing VPC."
    }
    precondition {
      condition     = data.aws_ami.selected.architecture == "arm64"
      error_message = "t4g.micro requires an ARM64 AMI."
    }
  }
}
