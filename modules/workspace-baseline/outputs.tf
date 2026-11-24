output "teams_folder" {
  description = "Workspace folder that holds one sub-folder per team."
  value       = databricks_directory.teams.path
}
