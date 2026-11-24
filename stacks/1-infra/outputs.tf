output "environment" {
  value = var.environment
}

output "workspace_id" {
  value = module.workspace.workspace_id
}

output "workspace_url" {
  value = module.workspace.workspace_url
}

output "metastore_id" {
  value = local.metastore_id
}

output "admins_group" {
  value = databricks_group.admins.display_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "nat_public_ips" {
  description = "Outbound IPs of the clusters. Add them to the allow lists of your data sources."
  value       = module.network.nat_public_ips
}

output "privatelink" {
  value = local.pl.enabled
}
