# ──────────────────────────────────────────────
# OUTPUTS
# Values printed to the terminal after apply.
# Useful for quickly grabbing resource info
# without digging through the AWS console.
# ──────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance — use this to SSH in"
  value       = aws_instance.web.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = aws_instance.web.public_dns
}

output "security_group_id" {
  description = "ID of the security group attached to the EC2 instance"
  value       = aws_security_group.lab_sg.id
}
