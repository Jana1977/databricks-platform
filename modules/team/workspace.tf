# ---------- entitlements ----------

resource "databricks_entitlements" "users" {
  provider              = databricks.workspace
  group_id              = databricks_group.this["users"].id
  workspace_access      = true
  databricks_sql_access = true
  depends_on            = [terraform_data.identities_ready]
}

resource "databricks_entitlements" "service_principal" {
  provider              = databricks.workspace
  for_each              = local.service_principals
  service_principal_id  = databricks_service_principal.this[each.key].id
  workspace_access      = true
  databricks_sql_access = true
  depends_on            = [terraform_data.identities_ready]
}

# ---------- team folder (/Teams/<team>) ----------
# The job repo uploads notebooks under <folder>/jobs/.

resource "databricks_directory" "team" {
  provider         = databricks.workspace
  path             = local.folder
  delete_recursive = var.force_destroy
}

resource "databricks_permissions" "team_folder" {
  provider       = databricks.workspace
  directory_path = databricks_directory.team.path

  access_control {
    group_name       = var.admins_group_name
    permission_level = "CAN_MANAGE"
  }

  access_control {
    group_name       = local.managers_group
    permission_level = "CAN_MANAGE"
  }

  access_control {
    group_name       = local.users_group
    permission_level = "CAN_READ"
  }

  access_control {
    service_principal_name = databricks_service_principal.this["deploy"].application_id
    permission_level       = "CAN_MANAGE"
  }

  depends_on = [terraform_data.identities_ready]
}

# ---------- secret scope ----------
# Managers put source-system passwords here; jobs (running as the deploy SP) read them.

resource "databricks_secret_scope" "team" {
  provider = databricks.workspace
  count    = local.team.secret_scope ? 1 : 0
  name     = local.team.name
}

resource "databricks_secret_acl" "managers" {
  provider   = databricks.workspace
  count      = length(databricks_secret_scope.team)
  scope      = databricks_secret_scope.team[0].name
  principal  = local.managers_group
  permission = "MANAGE"
  depends_on = [terraform_data.identities_ready]
}

resource "databricks_secret_acl" "service_principal" {
  provider   = databricks.workspace
  for_each   = local.team.secret_scope ? local.service_principals : {}
  scope      = databricks_secret_scope.team[0].name
  principal  = databricks_service_principal.this[each.key].application_id
  permission = "READ"
  depends_on = [terraform_data.identities_ready]
}
