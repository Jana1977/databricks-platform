# Stack 3: one module call per team file in teams/ whose `environments` includes this environment.
# Needs stacks 1 and 2. State: s3://<TF_STATE_BUCKET>/platform/<env>/3-teams.tfstate

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
  workspace  = data.terraform_remote_state.workspace.outputs
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/${var.environment}/1-infra.tfstate"
    region = local.c.aws.region
  }
}

data "terraform_remote_state" "workspace" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/${var.environment}/2-workspace.tfstate"
    region = local.c.aws.region
  }
}

module "team" {
  source   = "../../modules/team"
  for_each = module.config.teams

  providers = {
    aws                  = aws
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  team = each.value

  environment              = var.environment
  name_prefix              = local.c.name_prefix
  aws_account_id           = local.c.aws.account_id
  region                   = local.c.aws.region
  databricks_account_id    = local.c.databricks.account_id
  workspace_id             = local.infra.workspace_id
  workspace_url            = local.infra.workspace_url
  admins_group_name        = local.infra.admins_group
  teams_folder             = local.workspace.teams_folder
  state_bucket             = var.state_bucket
  github_oidc_provider_arn = local.n.github_oidc_provider_arn
  permissions_boundary_arn = local.n.permissions_boundary_arn
  create_users             = local.c.databricks.create_users
  force_destroy            = local.c.safety.allow_destroy_data
  tags                     = local.tags
}
