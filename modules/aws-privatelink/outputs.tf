output "rest_vpc_endpoint_id" {
  description = "Databricks ID of the back-end REST endpoint registration."
  value       = databricks_mws_vpc_endpoint.rest.vpc_endpoint_id
}

output "relay_vpc_endpoint_id" {
  description = "Databricks ID of the back-end relay endpoint registration."
  value       = databricks_mws_vpc_endpoint.relay.vpc_endpoint_id
}

output "frontend_vpc_endpoint_id" {
  value = try(databricks_mws_vpc_endpoint.frontend[0].vpc_endpoint_id, null)
}

output "private_access_settings_id" {
  value = databricks_mws_private_access_settings.this.private_access_settings_id
}
