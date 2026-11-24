output "config" {
  description = "Typed config with defaults filled in."
  value       = local.c
}

output "teams" {
  description = "Team files (decoded) whose environments list includes this environment."
  value       = local.teams
}

output "names" {
  description = "Names derived from the config, used by every stack."
  value = {
    name                     = local.name
    workspace_name           = local.c.databricks.workspace_name != "" ? local.c.databricks.workspace_name : local.name
    admins_group             = "${local.name}-platform-admins"
    permissions_boundary_arn = "arn:aws:iam::${local.c.aws.account_id}:policy/${local.name}-boundary"
    github_oidc_provider_arn = "arn:aws:iam::${local.c.aws.account_id}:oidc-provider/token.actions.githubusercontent.com"
    platform_catalog         = "${var.environment}_platform"
  }
}

output "tags" {
  description = "Tags for every AWS resource and the workspace."
  value = merge(
    {
      environment = var.environment
      platform    = "databricks"
      managed_by  = "terraform"
    },
    local.c.tags
  )
}

output "checked" {
  description = "Reference this so dependent resources wait for the checks."
  value       = terraform_data.checks.id
}
