output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private (NAT egress) subnet IDs."
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "Isolated data-tier subnet IDs."
  value       = aws_subnet.data[*].id
}

output "has_nat" {
  description = "Whether private subnets have internet egress through NAT."
  value       = local.nat_count > 0
}
