
output "instance_id" {
  description = "Observability EC2 instance ID"
  value       = aws_instance.observability.id
}

output "instance_public_ip" {
  description = "EC2 public IP address"
  value       = aws_instance.observability.public_ip
}

output "instance_private_ip" {
  description = "EC2 private IP address"
  value       = aws_instance.observability.private_ip
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.observability.instance_type
}

output "instance_state" {
  description = "EC2 instance state"
  value       = aws_instance.observability.instance_state
}
