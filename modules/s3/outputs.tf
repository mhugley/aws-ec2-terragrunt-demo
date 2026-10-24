output "bucket_name" {
  description = "Name of the private demo data bucket."
  value       = aws_s3_bucket.data.id
}
output "bucket_arn" {
  description = "ARN of the private demo data bucket."
  value       = aws_s3_bucket.data.arn
}
