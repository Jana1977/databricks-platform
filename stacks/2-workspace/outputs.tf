output "teams_folder" {
  value = module.baseline.teams_folder
}

output "platform_catalog" {
  value = try(databricks_catalog.platform[0].name, null)
}
