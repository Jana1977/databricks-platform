# Team catalog <env>_<team> with its own bucket, bound to this workspace only.

module "storage" {
  source = "../uc-storage"
  providers = {
    aws        = aws
    databricks = databricks.workspace
  }

  name                     = local.p
  bucket_name              = "${local.p}-${var.aws_account_id}"
  aws_account_id           = var.aws_account_id
  permissions_boundary_arn = var.permissions_boundary_arn
  force_destroy            = var.force_destroy
  comment                  = "Team ${local.team.name}"
  tags                     = local.tags

  location_grants = [
    { principal = var.admins_group_name, privileges = ["ALL_PRIVILEGES"] },
    { principal = local.managers_group, privileges = ["READ_FILES"] },
    { principal = databricks_service_principal.this["deploy"].application_id, privileges = ["READ_FILES", "WRITE_FILES"] },
  ]

  depends_on = [terraform_data.identities_ready]
}

resource "databricks_catalog" "this" {
  provider       = databricks.workspace
  name           = local.catalog
  comment        = "Team ${local.team.name} (${var.environment}). ${local.team.description}"
  storage_root   = "${module.storage.url}managed"
  isolation_mode = "ISOLATED"
  force_destroy  = var.force_destroy

  properties = {
    team        = local.team.name
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "databricks_schema" "this" {
  provider      = databricks.workspace
  for_each      = toset(local.team.catalog.schemas)
  catalog_name  = databricks_catalog.this.name
  name          = each.value
  comment       = "Managed by Terraform"
  force_destroy = var.force_destroy
}

resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  catalog  = databricks_catalog.this.name

  grant {
    principal  = var.admins_group_name
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal  = local.managers_group
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal  = local.users_group
    privileges = ["BROWSE", "USE_CATALOG", "USE_SCHEMA", "SELECT", "EXECUTE", "READ_VOLUME"]
  }

  # The deploy service principal owns the team's jobs, so it writes the team's tables.
  grant {
    principal = databricks_service_principal.this["deploy"].application_id
    privileges = [
      "USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "CREATE_FUNCTION",
      "SELECT", "MODIFY", "READ_VOLUME", "WRITE_VOLUME", "EXECUTE",
    ]
  }

  dynamic "grant" {
    for_each = { for k, v in databricks_service_principal.this : k => v if k != "deploy" }
    content {
      principal  = grant.value.application_id
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "EXECUTE", "READ_VOLUME"]
    }
  }

  depends_on = [terraform_data.identities_ready]
}
