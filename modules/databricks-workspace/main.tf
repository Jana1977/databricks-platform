# Creates a Databricks workspace on AWS in a customer-managed VPC.
#
#   IAM cross-account role   -> lets Databricks launch EC2 in your VPC (restricted to this VPC + SG)
#   S3 root bucket           -> workspace system data (DBFS root)
#   Databricks account objects: credentials, storage configuration, network, workspace

locals {
  root_bucket = "${var.name}-${var.aws_account_id}-root"
  role_name   = "${var.name}-crossaccount"
}

# ---------- cross-account role ----------

data "databricks_aws_assume_role_policy" "this" {
  external_id = var.databricks_account_id
}

data "databricks_aws_crossaccount_policy" "this" {
  policy_type       = "restricted"
  aws_account_id    = var.aws_account_id
  region            = var.region
  vpc_id            = var.vpc_id
  security_group_id = var.security_group_id
}

resource "aws_iam_role" "crossaccount" {
  name                 = local.role_name
  assume_role_policy   = data.databricks_aws_assume_role_policy.this.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "crossaccount" {
  name   = "${local.role_name}-policy"
  role   = aws_iam_role.crossaccount.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# IAM is eventually consistent; Databricks validates the role as soon as the credentials are created.
resource "time_sleep" "iam" {
  create_duration = "30s"
  depends_on      = [aws_iam_role_policy.crossaccount]
}

resource "databricks_mws_credentials" "this" {
  credentials_name = "${var.name}-credentials"
  role_arn         = aws_iam_role.crossaccount.arn
  depends_on       = [time_sleep.iam]
}

# ---------- root bucket ----------

resource "aws_s3_bucket" "root" {
  bucket        = local.root_bucket
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = local.root_bucket })
}

resource "aws_s3_bucket_ownership_controls" "root" {
  bucket = aws_s3_bucket.root.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "root" {
  bucket                  = aws_s3_bucket.root.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root" {
  bucket = aws_s3_bucket.root.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "databricks_aws_bucket_policy" "root" {
  bucket                   = aws_s3_bucket.root.bucket
  databricks_e2_account_id = var.databricks_account_id
}

resource "aws_s3_bucket_policy" "root" {
  bucket     = aws_s3_bucket.root.id
  policy     = data.databricks_aws_bucket_policy.root.json
  depends_on = [aws_s3_bucket_public_access_block.root]
}

resource "databricks_mws_storage_configurations" "this" {
  account_id                 = var.databricks_account_id
  storage_configuration_name = "${var.name}-root"
  bucket_name                = aws_s3_bucket.root.bucket
}

# ---------- network ----------

resource "databricks_mws_networks" "this" {
  account_id         = var.databricks_account_id
  network_name       = "${var.name}-network"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]

  dynamic "vpc_endpoints" {
    for_each = var.private_link == null ? [] : [var.private_link]
    content {
      rest_api        = [vpc_endpoints.value.rest_vpc_endpoint_id]
      dataplane_relay = [vpc_endpoints.value.relay_vpc_endpoint_id]
    }
  }
}

# ---------- workspace ----------

resource "databricks_mws_workspaces" "this" {
  account_id                 = var.databricks_account_id
  workspace_name             = var.workspace_name
  aws_region                 = var.region
  credentials_id             = databricks_mws_credentials.this.credentials_id
  storage_configuration_id   = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id                 = databricks_mws_networks.this.network_id
  private_access_settings_id = var.private_link == null ? null : var.private_link.private_access_settings_id
  custom_tags                = var.tags

  depends_on = [aws_s3_bucket_policy.root]
}
