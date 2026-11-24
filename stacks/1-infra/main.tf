# Stack 1: AWS network + Databricks workspace + Unity Catalog metastore assignment + workspace admins.
# State: s3://<TF_STATE_BUCKET>/platform/<env>/1-infra.tfstate

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
  allow      = local.c.safety.allow_destroy_data
  uc         = local.c.unity_catalog
  pl         = local.c.network.privatelink
}

# Stop early if the credentials point at a different AWS account than the config.
data "aws_caller_identity" "current" {}

resource "terraform_data" "aws_account_guard" {
  input = data.aws_caller_identity.current.account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == local.c.aws.account_id
      error_message = "AWS credentials are for account ${data.aws_caller_identity.current.account_id}, but config/${var.environment}.yaml says ${local.c.aws.account_id}."
    }
  }
}

# ---------- optional flow-log bucket ----------

resource "aws_s3_bucket" "flow_logs" {
  count         = local.c.network.flow_logs ? 1 : 0
  bucket        = "${local.n.name}-${local.c.aws.account_id}-flowlogs"
  force_destroy = local.allow
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count                   = length(aws_s3_bucket.flow_logs)
  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = length(aws_s3_bucket.flow_logs)
  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  statement {
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${local.c.aws.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.c.aws.account_id]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs[0].arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.c.aws.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count      = length(aws_s3_bucket.flow_logs)
  bucket     = aws_s3_bucket.flow_logs[0].id
  policy     = data.aws_iam_policy_document.flow_logs[0].json
  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

# ---------- network ----------

module "network" {
  source = "../../modules/aws-network"

  name                       = local.n.name
  vpc_cidr                   = local.c.network.vpc_cidr
  private_subnet_cidrs       = local.c.network.private_subnet_cidrs
  public_subnet_cidrs        = local.c.network.public_subnet_cidrs
  availability_zones         = local.c.network.availability_zones
  nat_gateway_count          = local.c.network.nat_gateway_count
  enable_interface_endpoints = local.c.network.interface_endpoints
  enable_flow_logs           = local.c.network.flow_logs
  # Referencing the policy makes the flow log wait until log delivery is allowed.
  flow_logs_bucket_arn = local.c.network.flow_logs ? "arn:aws:s3:::${aws_s3_bucket_policy.flow_logs[0].bucket}" : ""
  tags                 = local.tags
}

module "privatelink" {
  source    = "../../modules/aws-privatelink"
  count     = local.pl.enabled ? 1 : 0
  providers = { aws = aws, databricks = databricks.account }

  name                      = local.n.name
  region                    = local.c.aws.region
  databricks_account_id     = local.c.databricks.account_id
  vpc_id                    = module.network.vpc_id
  availability_zones        = module.network.availability_zones
  subnet_cidrs              = local.pl.subnet_cidrs
  compute_security_group_id = module.network.security_group_id
  workspace_service_name    = local.pl.workspace_service
  relay_service_name        = local.pl.relay_service
  public_access_enabled     = local.pl.public_access_enabled
  frontend                  = local.pl.frontend
  tags                      = local.tags
}

# ---------- workspace ----------

module "workspace" {
  source    = "../../modules/databricks-workspace"
  providers = { aws = aws, databricks = databricks.account }

  name                     = local.n.name
  workspace_name           = local.n.workspace_name
  databricks_account_id    = local.c.databricks.account_id
  aws_account_id           = local.c.aws.account_id
  region                   = local.c.aws.region
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_subnet_ids
  security_group_id        = module.network.security_group_id
  permissions_boundary_arn = local.n.permissions_boundary_arn
  force_destroy            = local.allow
  tags                     = local.tags

  private_link = local.pl.enabled ? {
    rest_vpc_endpoint_id       = module.privatelink[0].rest_vpc_endpoint_id
    relay_vpc_endpoint_id      = module.privatelink[0].relay_vpc_endpoint_id
    private_access_settings_id = module.privatelink[0].private_access_settings_id
  } : null
}

# ---------- Unity Catalog metastore ----------
# One metastore per region per Databricks account.
#   metastore_id set         -> use that metastore
#   create_metastore: true   -> create one (only if the region has none)
#   neither                  -> use the metastore that already exists in the region

data "databricks_metastore" "region" {
  provider = databricks.account
  count    = local.uc.metastore_id == "" && !local.uc.create_metastore ? 1 : 0
  region   = local.c.aws.region
}

resource "databricks_metastore" "this" {
  provider      = databricks.account
  count         = local.uc.create_metastore ? 1 : 0
  name          = "${local.c.name_prefix}-${local.c.aws.region}"
  region        = local.c.aws.region
  owner         = databricks_group.admins.display_name
  force_destroy = false
}

locals {
  metastore_id = (
    local.uc.metastore_id != "" ? local.uc.metastore_id :
    local.uc.create_metastore ? databricks_metastore.this[0].id :
    try(data.databricks_metastore.region[0].metastore_info[0].metastore_id, data.databricks_metastore.region[0].metastore_id)
  )
}

resource "databricks_metastore_assignment" "this" {
  provider     = databricks.account
  count        = local.uc.assign_metastore ? 1 : 0
  workspace_id = module.workspace.workspace_id
  metastore_id = local.metastore_id
}

# ---------- platform admins ----------

data "databricks_user" "admin" {
  provider  = databricks.account
  for_each  = local.c.databricks.create_users ? toset([]) : toset(local.c.databricks.admins)
  user_name = each.value
}

resource "databricks_user" "admin" {
  provider  = databricks.account
  for_each  = local.c.databricks.create_users ? toset(local.c.databricks.admins) : toset([])
  user_name = each.value
  force     = true
}

resource "databricks_group" "admins" {
  provider     = databricks.account
  display_name = local.n.admins_group
}

resource "databricks_group_member" "admin" {
  provider  = databricks.account
  for_each  = toset(local.c.databricks.admins)
  group_id  = databricks_group.admins.id
  member_id = local.c.databricks.create_users ? databricks_user.admin[each.value].id : data.databricks_user.admin[each.value].id
}

# The CI service principal (DATABRICKS_CLIENT_ID) joins the admins group, so it can manage
# the workspace in stacks 2 and 3.
data "databricks_service_principal" "ci" {
  provider       = databricks.account
  count          = var.ci_client_id != "" ? 1 : 0
  application_id = var.ci_client_id
}

resource "databricks_group_member" "ci" {
  provider  = databricks.account
  count     = length(data.databricks_service_principal.ci)
  group_id  = databricks_group.admins.id
  member_id = data.databricks_service_principal.ci[0].id
}

# Assigning account groups to a workspace needs identity federation, which comes with Unity Catalog.
resource "databricks_mws_permission_assignment" "admins" {
  provider     = databricks.account
  workspace_id = module.workspace.workspace_id
  principal_id = databricks_group.admins.id
  permissions  = ["ADMIN"]

  depends_on = [databricks_metastore_assignment.this]
}
