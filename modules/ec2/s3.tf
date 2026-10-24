# Keep the existing stack/state addresses for EC2 while adding a reusable S3 module.
module "data_bucket" {
  source      = "../s3"
  bucket_name = "mhugley-ec2-demo-data-283678155577-us-east-1"
}
output "data_bucket_name" {
  description = "Private demo S3 bucket name."
  value       = module.data_bucket.bucket_name
}
output "data_bucket_arn" {
  description = "Private demo S3 bucket ARN."
  value       = module.data_bucket.bucket_arn
}
