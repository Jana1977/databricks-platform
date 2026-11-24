output "teams" {
  description = "What was created per team."
  value = {
    for k, t in module.team : k => {
      catalog            = t.catalog
      groups             = t.groups
      service_principals = t.service_principals
      job_policy         = t.job_policy
      warehouse_id       = t.warehouse_id
      folder             = t.folder
    }
  }
}

output "team_handoff" {
  description = "GitHub environment variables for each team's job repo. The deploy workflow prints these."
  value       = { for k, t in module.team : k => t.handoff }
}
