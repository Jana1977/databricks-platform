output "catalog" {
  value = databricks_catalog.this.name
}

output "groups" {
  description = "Account group names by key (users, managers, extra groups)."
  value       = { for k, g in databricks_group.this : k => g.display_name }
}

output "service_principals" {
  description = "Service principal application IDs by key."
  value       = { for k, s in databricks_service_principal.this : k => s.application_id }
}

output "job_policy" {
  value = databricks_cluster_policy.job.name
}

output "warehouse_id" {
  value = try(databricks_sql_endpoint.this[0].id, null)
}

output "folder" {
  value = databricks_directory.team.path
}

# Everything the team's job repo needs: GitHub environment variables, and which repos may use them.
output "handoff" {
  value = {
    job_repos = local.team.job_repos
    variables = {
      TEAM             = local.team.name
      DATABRICKS_HOST  = var.workspace_url
      AWS_REGION       = var.region
      AWS_ROLE_ARN     = try(aws_iam_role.jobs_ci[0].arn, "")
      TF_STATE_BUCKET  = var.state_bucket
      DEPLOY_SECRET_ID = aws_secretsmanager_secret.deploy.name
      NAME_PREFIX      = var.name_prefix
    }
  }
}
