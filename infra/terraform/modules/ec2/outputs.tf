output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "EIP if associated, else instance public IP (changes on stop/start without EIP)"
  value       = var.associate_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "ssh_command" {
  value = var.ssh_key_name == null ? "aws ssm start-session --target ${aws_instance.this.id}" : "ssh ubuntu@${var.associate_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip}"
}
