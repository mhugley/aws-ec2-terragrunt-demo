variable "region" {
  description = "AWS deployment region."
  type        = string
  default     = "us-east-1"
}
variable "vpc_id" {
  description = "Existing VPC; this module never manages the VPC."
  type        = string
}
variable "subnet_id" {
  description = "Existing private subnet in the selected VPC."
  type        = string
}
variable "ami_id" {
  description = "Pinned Amazon Linux 2023 ARM64 AMI; upgrade deliberately in a PR."
  type        = string
}
variable "instance_type" {
  description = "Cost guardrail: only the approved micro instance is allowed."
  type        = string
  default     = "t4g.micro"
  validation {
    condition     = var.instance_type == "t4g.micro"
    error_message = "This demo is restricted to t4g.micro."
  }
}
