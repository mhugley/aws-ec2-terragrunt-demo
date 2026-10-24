terraform {
  required_version = ">= 1.15.4, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["283678155577"]
  default_tags {
    tags = { Project = "ec2-terragrunt-demo", ManagedBy = "Terraform" }
  }
}
locals {
  bucket     = "mhugley-ec2-demo-tfstate-283678155577-us-east-1"
  account    = "283678155577"
  region     = "us-east-1"
  project    = "ec2-terragrunt-demo"
  repository = "mhugley/aws-ec2-terragrunt-demo"
  prefix     = "arn:aws:ec2:us-east-1:283678155577"
}
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter { prefix = "" }
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_iam_role" "github" {
  for_each             = toset(["plan", "deploy"])
  name                 = "ec2-terragrunt-demo-${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = each.key == "deploy" ? ["repo:${local.repository}:environment:dev"] : ["repo:${local.repository}:ref:refs/heads/main", "repo:${local.repository}:pull_request"]
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "state" {
  for_each = aws_iam_role.github
  name     = "scoped-state-and-read"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn,
      Condition = { StringLike = { "s3:prefix" = ["dev/ec2/*", "env:/*"] } } },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.state.arn}/dev/ec2/terraform.tfstate" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/dev/ec2/terraform.tfstate.tflock" },
      { Effect = "Allow", Action = ["ec2:Describe*"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = local.region } } }
    ]
  })
}
resource "aws_iam_role_policy" "deploy" {
  name = "scoped-ec2-deployment"
  role = aws_iam_role.github["deploy"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.state.arn}/dev/ec2/terraform.tfstate" },
      { Sid      = "LaunchExistingNetwork", Effect = "Allow", Action = ["ec2:RunInstances"],
        Resource = ["arn:aws:ec2:us-east-1::image/ami-07890d146f8d6ee5b", "${local.prefix}:subnet/subnet-06218381657578b32", "${local.prefix}:security-group/*", "${local.prefix}:network-interface/*"],
      Condition = { StringEquals = { "aws:RequestedRegion" = local.region } } },
      { Sid = "LaunchMicroOnly", Effect = "Allow", Action = ["ec2:RunInstances"], Resource = "${local.prefix}:instance/*",
      Condition = { StringEquals = { "ec2:InstanceType" = "t4g.micro", "aws:RequestTag/Project" = local.project } } },
      { Sid = "DenyPublicAddress", Effect = "Deny", Action = ["ec2:RunInstances"], Resource = "*", Condition = { Bool = { "ec2:AssociatePublicIpAddress" = "true" } } },
      { Sid = "LaunchEncryptedVolume", Effect = "Allow", Action = ["ec2:RunInstances"], Resource = "${local.prefix}:volume/*", Condition = { Bool = { "ec2:Encrypted" = "true" } } },
      { Sid = "CreateSecurityGroup", Effect = "Allow", Action = ["ec2:CreateSecurityGroup"], Resource = ["${local.prefix}:security-group/*", "${local.prefix}:vpc/vpc-0b57a3944dfc414b6"],
      Condition = { StringEquals = { "aws:RequestTag/Project" = local.project, "aws:RequestedRegion" = local.region } } },
      { Sid = "TagOnCreate", Effect = "Allow", Action = ["ec2:CreateTags"], Resource = ["${local.prefix}:instance/*", "${local.prefix}:volume/*", "${local.prefix}:security-group/*", "${local.prefix}:network-interface/*"], Condition = { StringEquals = { "ec2:CreateAction" = ["RunInstances", "CreateSecurityGroup"] } } },
      { Sid = "ManageProjectResources", Effect = "Allow", Action = ["ec2:TerminateInstances", "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceCreditSpecification", "ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:CreateTags", "ec2:DeleteTags"],
      Resource = ["${local.prefix}:instance/*", "${local.prefix}:volume/*", "${local.prefix}:security-group/*"], Condition = { StringEquals = { "ec2:ResourceTag/Project" = local.project, "aws:RequestedRegion" = local.region } } }
    ]
  })
}
output "plan_role_arn" {
  description = "Read-only plan role, with write access only to its state lock."
  value       = aws_iam_role.github["plan"].arn
}
output "deploy_role_arn" {
  description = "Deployment role restricted to this project and existing network."
  value       = aws_iam_role.github["deploy"].arn
}
output "state_bucket" {
  description = "Versioned, encrypted, private state bucket."
  value       = aws_s3_bucket.state.id
}
