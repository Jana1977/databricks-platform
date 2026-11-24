output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Subnets the workspace launches clusters into."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "availability_zones" {
  value = local.azs
}

output "security_group_id" {
  description = "Security group for cluster nodes."
  value       = aws_security_group.workspace.id
}

output "nat_public_ips" {
  description = "Outbound IPs of the cluster nodes (add these to allow lists of your data sources)."
  value       = aws_eip.nat[*].public_ip
}
