output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.demo.id
}
output "private_ip" {
  description = "Private IPv4 address; no public address is allocated."
  value       = aws_instance.demo.private_ip
}
output "security_group_id" {
  description = "Dedicated security group with no ingress or egress rules."
  value       = aws_security_group.instance.id
}
