# ---------- users ----------

data "databricks_user" "member" {
  provider  = databricks.account
  for_each  = var.create_users ? toset([]) : local.all_users
  user_name = each.value
}

resource "databricks_user" "member" {
  provider  = databricks.account
  for_each  = var.create_users ? local.all_users : toset([])
  user_name = each.value
  # Adopt the user if it already exists instead of failing.
  force = true
}

locals {
  user_ids = var.create_users ? { for k, u in databricks_user.member : k => u.id } : { for k, u in data.databricks_user.member : k => u.id }
}

# ---------- groups ----------

resource "databricks_group" "this" {
  provider     = databricks.account
  for_each     = local.groups
  display_name = each.value.name
}

resource "databricks_group_member" "user" {
  provider  = databricks.account
  for_each  = local.memberships
  group_id  = databricks_group.this[each.value.group].id
  member_id = local.user_ids[each.value.user]
}

# ---------- service principals ----------

resource "databricks_service_principal" "this" {
  provider     = databricks.account
  for_each     = local.service_principals
  display_name = each.value
}

resource "databricks_group_member" "service_principal" {
  provider  = databricks.account
  for_each  = local.service_principals
  group_id  = databricks_group.this["users"].id
  member_id = databricks_service_principal.this[each.key].id
}

# Team managers may use the deploy service principal (for example "run as" in jobs).
resource "databricks_access_control_rule_set" "deploy" {
  provider = databricks.account
  name     = "accounts/${var.databricks_account_id}/servicePrincipals/${databricks_service_principal.this["deploy"].application_id}/ruleSets/default"

  grant_rules {
    principals = ["groups/${databricks_group.this["managers"].display_name}"]
    role       = "roles/servicePrincipal.user"
  }
}

# OAuth secret the job repo uses to deploy. Replaced every secret_rotation_days.
resource "time_rotating" "deploy_secret" {
  rotation_days = var.secret_rotation_days
}

resource "databricks_service_principal_secret" "deploy" {
  provider             = databricks.account
  service_principal_id = databricks_service_principal.this["deploy"].id
  lifetime             = "${var.secret_lifetime_days * 86400}s"
  time_rotating        = "rotated-${time_rotating.deploy_secret.rfc3339}"

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.secret_rotation_days < var.secret_lifetime_days
      error_message = "secret_rotation_days must be shorter than secret_lifetime_days."
    }
  }
}

# ---------- workspace access ----------

resource "databricks_mws_permission_assignment" "group" {
  provider     = databricks.account
  for_each     = local.groups
  workspace_id = var.workspace_id
  principal_id = databricks_group.this[each.key].id
  permissions  = ["USER"]
}

resource "databricks_mws_permission_assignment" "service_principal" {
  provider     = databricks.account
  for_each     = local.service_principals
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.this[each.key].id
  permissions  = ["USER"]
}

# Workspace-level objects below reference groups and service principals by name,
# so they must wait until the identities are assigned to the workspace.
resource "terraform_data" "identities_ready" {
  input = {
    groups = [for k, v in databricks_mws_permission_assignment.group : v.id]
    sps    = [for k, v in databricks_mws_permission_assignment.service_principal : v.id]
  }
}
