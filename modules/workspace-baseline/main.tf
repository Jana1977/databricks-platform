# Workspace-wide settings that every environment gets.
# Uses the workspace-level provider.

resource "databricks_workspace_conf" "this" {
  custom_config = merge(
    {
      "maxTokenLifetimeDays" = tostring(var.token_max_lifetime_days)
    },
    length(var.ip_allow_list) > 0 ? { "enableIpAccessLists" = "true" } : {}
  )
}

resource "databricks_ip_access_list" "allow" {
  count        = length(var.ip_allow_list) > 0 ? 1 : 0
  label        = "allowed"
  list_type    = "ALLOW"
  ip_addresses = var.ip_allow_list
  depends_on   = [databricks_workspace_conf.this]
}

# Workspace admins cannot create tokens for, or run jobs as, other identities.
resource "databricks_restrict_workspace_admins_setting" "this" {
  count = var.restrict_workspace_admins ? 1 : 0
  restrict_workspace_admins {
    status = "RESTRICT_TOKENS_AND_JOB_RUN_AS"
  }
}

# No Hive metastore, DBFS mounts or no-isolation clusters: Unity Catalog only.
resource "databricks_disable_legacy_access_setting" "this" {
  count = var.disable_legacy_features ? 1 : 0
  disable_legacy_access {
    value = true
  }
}

resource "databricks_disable_legacy_dbfs_setting" "this" {
  count = var.disable_legacy_features ? 1 : 0
  disable_legacy_dbfs {
    value = true
  }
}

# Built-in "users" group: can log in and use SQL, cannot create clusters freely
# (teams get cluster policies instead).
#data "databricks_group" "users" {
#  display_name = "users"
#}

#resource "databricks_entitlements" "users" {
#  group_id              = data.databricks_group.users.id
#  workspace_access      = true
#  databricks_sql_access = true
#  allow_cluster_create  = false
#}

# Parent folder for every team's folder (/Teams/<team>).
resource "databricks_directory" "teams" {
  path = "/Teams"
}

resource "databricks_permissions" "teams" {
  directory_path = databricks_directory.teams.path

  access_control {
    group_name       = var.admins_group_name
    permission_level = "CAN_MANAGE"
  }
}
