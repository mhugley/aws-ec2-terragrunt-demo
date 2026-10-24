locals {
  data_bucket_arn = "arn:aws:s3:::mhugley-ec2-demo-data-283678155577-us-east-1"
}
# Administrator-managed permissions. The workflow cannot change its own IAM role.
resource "aws_iam_role_policy" "data_bucket_read" {
  for_each = aws_iam_role.github
  name     = "scoped-demo-s3-read"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration", "s3:ListBucket"
      ]
      Resource = local.data_bucket_arn
    }]
  })
}
resource "aws_iam_role_policy" "data_bucket_deploy" {
  name = "scoped-demo-s3-deploy"
  role = aws_iam_role.github["deploy"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketOwnershipControls",
        "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutLifecycleConfiguration"
      ]
      Resource  = local.data_bucket_arn
      Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
    }]
  })
}
