# Stack 2: settings inside the workspace + the shared <env>_platform catalog.
# Needs stack 1. State: s3://<TF_STATE_BUCKET>/platform/<env>/2-workspace.tfstate

module "config" {
  source      = "../../modules/platform-config"
  environment = var.environment
  config_raw  = local.raw
  config      = local.raw
  teams_dir   = local.teams_dir
}

locals {
  config_dir = var.config_dir != "" ? var.config_dir : "${path.root}/../../config"
  teams_dir  = var.teams_dir != "" ? var.teams_dir : "${path.root}/../../teams"
  raw        = yamldecode(file("${local.config_dir}/${var.environment}.yaml"))
  c          = module.config.config
  n          = module.config.names
  tags       = module.config.tags
  infra      = data.terraform_remote_state.infra.outputs
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/${var.environment}/1-infra.tfstate"
    region = local.c.aws.region
  }
}

module "baseline" {
  source = "../../modules/workspace-baseline"

  admins_group_name         = local.infra.admins_group
  token_max_lifetime_days   = local.c.workspace.token_max_lifetime_days
  ip_allow_list             = local.c.workspace.ip_allow_list
  restrict_workspace_admins = local.c.workspace.restrict_workspace_admins
  disable_legacy_features   = local.c.workspace.disable_legacy_features
}

# ---------- <env>_platform catalog (shared, read-only for everyone) ----------

module "platform_storage" {
  source = "../../modules/uc-storage"
  count  = local.c.unity_catalog.platform_catalog ? 1 : 0

  name                     = "${local.n.name}-platform"
  bucket_name              = "${local.n.name}-platform-${local.c.aws.account_id}"
  aws_account_id           = local.c.aws.account_id
  permissions_boundary_arn = local.n.permissions_boundary_arn
  force_destroy            = local.c.safety.allow_destroy_data
  comment                  = "Shared platform catalog"
  tags                     = local.tags

  location_grants = [
    { principal = local.infra.admins_group, privileges = ["ALL_PRIVILEGES"] },
  ]
}

resource "databricks_catalog" "platform" {
  count          = local.c.unity_catalog.platform_catalog ? 1 : 0
  name           = local.n.platform_catalog
  comment        = "Shared reference data for every team in ${var.environment}"
  storage_root   = "${module.platform_storage[0].url}managed"
  isolation_mode = "ISOLATED"
  force_destroy  = local.c.safety.allow_destroy_data

  properties = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "databricks_schema" "shared" {
  count         = length(databricks_catalog.platform)
  catalog_name  = databricks_catalog.platform[0].name
  name          = "shared"
  comment       = "Reference data shared by all teams"
  force_destroy = local.c.safety.allow_destroy_data
}

resource "databricks_grants" "platform" {
  count   = length(databricks_catalog.platform)
  catalog = databricks_catalog.platform[0].name

  grant {
    principal  = local.infra.admins_group
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal  = "account users"
    privileges = ["BROWSE", "USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}
