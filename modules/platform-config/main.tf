# Reads and checks the platform config and the team files. No cloud resources.
# Any problem found here stops `terraform plan` with a readable error.

locals {
  c    = var.config
  name = "${local.c.name_prefix}-${var.environment}"

  # ---------- allowed keys (catch typos such as "nat_gatway_count") ----------
  allowed = {
    top           = ["environment", "name_prefix", "aws", "databricks", "unity_catalog", "network", "workspace", "safety", "tags"]
    aws           = ["account_id", "region"]
    databricks    = ["account_id", "workspace_name", "admins", "create_users"]
    unity_catalog = ["metastore_id", "create_metastore", "assign_metastore", "platform_catalog"]
    network       = ["vpc_cidr", "private_subnet_cidrs", "public_subnet_cidrs", "availability_zones", "nat_gateway_count", "interface_endpoints", "flow_logs", "privatelink"]
    privatelink   = ["enabled", "subnet_cidrs", "public_access_enabled", "workspace_service", "relay_service", "frontend"]
    workspace     = ["token_max_lifetime_days", "ip_allow_list", "restrict_workspace_admins", "disable_legacy_features"]
    safety        = ["allow_destroy_data"]
  }

  raw = var.config_raw
  config_unknown_keys = concat(
    [for k in keys(local.raw) : k if !contains(local.allowed.top, k)],
    [for k in keys(try(local.raw.aws, {})) : "aws.${k}" if !contains(local.allowed.aws, k)],
    [for k in keys(try(local.raw.databricks, {})) : "databricks.${k}" if !contains(local.allowed.databricks, k)],
    [for k in keys(try(local.raw.unity_catalog, {})) : "unity_catalog.${k}" if !contains(local.allowed.unity_catalog, k)],
    [for k in keys(try(local.raw.network, {})) : "network.${k}" if !contains(local.allowed.network, k)],
    [for k in keys(try(local.raw.network.privatelink, {})) : "network.privatelink.${k}" if !contains(local.allowed.privatelink, k)],
    [for k in keys(try(local.raw.workspace, {})) : "workspace.${k}" if !contains(local.allowed.workspace, k)],
    [for k in keys(try(local.raw.safety, {})) : "safety.${k}" if !contains(local.allowed.safety, k)],
  )

  team_allowed = {
    top           = ["name", "description", "environments", "managers", "members", "groups", "service_principals", "job_repos", "compute", "sql_warehouse", "catalog", "secret_scope", "budget"]
    compute       = ["node_types", "max_workers", "allow_interactive", "autotermination_minutes", "max_clusters_per_user"]
    sql_warehouse = ["enabled", "size", "auto_stop_minutes", "max_clusters", "serverless"]
    catalog       = ["schemas"]
    budget        = ["monthly_usd", "alert_emails"]
  }

  # ---------- teams ----------
  team_files = [for f in fileset(var.teams_dir, "*.yaml") : f if !startswith(f, "_")]
  teams_all  = { for f in local.team_files : trimsuffix(f, ".yaml") => yamldecode(file("${var.teams_dir}/${f}")) }

  team_problems = flatten([
    for file, t in local.teams_all : concat(
      try(t.name, "") == file ? [] : ["teams/${file}.yaml: name must be \"${file}\" (same as the file name)"],
      length(try(t.environments, [])) > 0 ? [] : ["teams/${file}.yaml: environments must list at least one environment, for example [int]"],
      [for k in keys(t) : "teams/${file}.yaml: unknown key ${k}" if !contains(local.team_allowed.top, k)],
      [for s in ["compute", "sql_warehouse", "catalog", "budget"] :
        [for k in keys(try(t[s], {})) : "teams/${file}.yaml: unknown key ${s}.${k}" if !contains(local.team_allowed[s], k)]
      ]...
    )
  ])

  teams = { for k, t in local.teams_all : k => t if contains(try(t.environments, []), var.environment) }

  privatelink_ok = !local.c.network.privatelink.enabled || length(local.c.network.privatelink.subnet_cidrs) > 0
}

resource "terraform_data" "checks" {
  input = local.name

  lifecycle {
    precondition {
      condition     = local.c.environment == var.environment
      error_message = "config/${var.environment}.yaml says environment: ${local.c.environment}. It must be ${var.environment}."
    }
    precondition {
      condition     = length(local.config_unknown_keys) == 0
      error_message = "config/${var.environment}.yaml has unknown keys: ${join(", ", local.config_unknown_keys)}."
    }
    precondition {
      condition     = can(regex("^[a-z][a-z0-9]{1,9}$", local.c.name_prefix))
      error_message = "name_prefix must be 2-10 lower-case letters/digits."
    }
    precondition {
      condition     = can(regex("^[0-9]{12}$", local.c.aws.account_id))
      error_message = "aws.account_id must be the 12-digit AWS account ID (quote it in YAML)."
    }
    precondition {
      condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", local.c.aws.region))
      error_message = "aws.region must look like us-east-1."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", local.c.databricks.account_id))
      error_message = "databricks.account_id must be the account ID from the Databricks account console (a UUID)."
    }
    precondition {
      condition     = length(local.c.databricks.admins) > 0
      error_message = "databricks.admins needs at least one e-mail address."
    }
    precondition {
      condition     = !(local.c.unity_catalog.create_metastore && local.c.unity_catalog.metastore_id != "")
      error_message = "Set either unity_catalog.metastore_id or unity_catalog.create_metastore: true, not both."
    }
    precondition {
      condition     = local.privatelink_ok
      error_message = "network.privatelink.enabled is true, so network.privatelink.subnet_cidrs needs at least one subnet."
    }
    precondition {
      condition     = length(local.team_problems) == 0
      error_message = "Team files have problems:\n  ${join("\n  ", local.team_problems)}"
    }
  }
}
