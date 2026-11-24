# Cluster policies: what clusters the team may start, and the team SQL warehouse.
# Every cluster gets the tags team=<team> and environment=<env>, which the budget filters on.

locals {
  nodes = local.team.compute.node_types
  max   = local.team.compute.max_workers

  policy_base = {
    "spark_version"               = { type = "unlimited", defaultValue = "auto:latest-lts" }
    "node_type_id"                = { type = "allowlist", values = local.nodes, defaultValue = local.nodes[0] }
    "driver_node_type_id"         = { type = "allowlist", values = local.nodes, defaultValue = local.nodes[0] }
    "num_workers"                 = { type = "range", minValue = 0, maxValue = local.max, defaultValue = 1, isOptional = true }
    "autoscale.max_workers"       = { type = "range", maxValue = local.max, isOptional = true }
    "data_security_mode"          = { type = "allowlist", values = ["SINGLE_USER", "USER_ISOLATION"], defaultValue = "SINGLE_USER" }
    "aws_attributes.availability" = { type = "allowlist", values = ["SPOT_WITH_FALLBACK", "ON_DEMAND"], defaultValue = "SPOT_WITH_FALLBACK" }
    "instance_pool_id"            = { type = "forbidden", hidden = true }
    "custom_tags.team"            = { type = "fixed", value = local.team.name }
    "custom_tags.environment"     = { type = "fixed", value = var.environment }
  }

  job_policy = merge(local.policy_base, {
    "cluster_type" = { type = "fixed", value = "job" }
  })

  interactive_policy = merge(local.policy_base, {
    "cluster_type"            = { type = "fixed", value = "all-purpose" }
    "autotermination_minutes" = { type = "range", minValue = 10, maxValue = local.team.compute.autotermination_minutes, defaultValue = local.team.compute.autotermination_minutes }
  })

  # Service principals other than deploy.
  extra_sps = { for k, v in databricks_service_principal.this : k => v if k != "deploy" }
}

# ---------- job clusters ----------

resource "databricks_cluster_policy" "job" {
  provider    = databricks.workspace
  name        = "${local.team.name}-job-policy"
  description = "Job clusters for team ${local.team.name}"
  definition  = jsonencode(local.job_policy)
}

resource "databricks_permissions" "job_policy" {
  provider          = databricks.workspace
  cluster_policy_id = databricks_cluster_policy.job.id

  access_control {
    service_principal_name = databricks_service_principal.this["deploy"].application_id
    permission_level       = "CAN_USE"
  }

  access_control {
    group_name       = local.managers_group
    permission_level = "CAN_USE"
  }

  dynamic "access_control" {
    for_each = local.extra_sps
    content {
      service_principal_name = access_control.value.application_id
      permission_level       = "CAN_USE"
    }
  }

  depends_on = [terraform_data.identities_ready]
}

# ---------- interactive (all-purpose) clusters ----------

resource "databricks_cluster_policy" "interactive" {
  provider              = databricks.workspace
  count                 = local.team.compute.allow_interactive ? 1 : 0
  name                  = "${local.team.name}-interactive-policy"
  description           = "Notebook clusters for team ${local.team.name}"
  definition            = jsonencode(local.interactive_policy)
  max_clusters_per_user = local.team.compute.max_clusters_per_user
}

resource "databricks_permissions" "interactive_policy" {
  provider          = databricks.workspace
  count             = length(databricks_cluster_policy.interactive)
  cluster_policy_id = databricks_cluster_policy.interactive[0].id

  access_control {
    group_name       = local.users_group
    permission_level = "CAN_USE"
  }

  depends_on = [terraform_data.identities_ready]
}

# ---------- SQL warehouse ----------

resource "databricks_sql_endpoint" "this" {
  provider                  = databricks.workspace
  count                     = local.team.sql_warehouse.enabled ? 1 : 0
  name                      = "${local.team.name}-warehouse"
  cluster_size              = local.team.sql_warehouse.size
  auto_stop_mins            = local.team.sql_warehouse.auto_stop_minutes
  min_num_clusters          = 1
  max_num_clusters          = local.team.sql_warehouse.max_clusters
  warehouse_type            = "PRO"
  enable_serverless_compute = local.team.sql_warehouse.serverless

  tags {
    custom_tags {
      key   = "team"
      value = local.team.name
    }
    custom_tags {
      key   = "environment"
      value = var.environment
    }
  }
}

resource "databricks_permissions" "warehouse" {
  provider        = databricks.workspace
  count           = length(databricks_sql_endpoint.this)
  sql_endpoint_id = databricks_sql_endpoint.this[0].id

  access_control {
    group_name       = local.managers_group
    permission_level = "CAN_MANAGE"
  }

  access_control {
    group_name       = local.users_group
    permission_level = "CAN_USE"
  }

  access_control {
    service_principal_name = databricks_service_principal.this["deploy"].application_id
    permission_level       = "CAN_USE"
  }

  dynamic "access_control" {
    for_each = local.extra_sps
    content {
      service_principal_name = access_control.value.application_id
      permission_level       = "CAN_USE"
    }
  }

  depends_on = [terraform_data.identities_ready]
}
