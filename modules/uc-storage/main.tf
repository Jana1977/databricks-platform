# Storage for Unity Catalog: an S3 bucket, the IAM role Unity Catalog assumes,
# a storage credential and an external location over the whole bucket.
#
# Order matters (Databricks gives the external ID only after the credential exists):
#   1. storage credential (points at the role ARN by name, role not created yet)
#   2. IAM role trusting the Unity Catalog master role with that external ID, plus itself
#   3. wait for IAM to propagate
#   4. external location (Databricks validates the role here)

data "aws_partition" "current" {}

locals {
  role_name = "${var.name}-uc"
  role_arn  = "arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:role/${local.role_name}"
}

# ---------- bucket ----------

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Disabled"
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket     = aws_s3_bucket.this.id
  policy     = data.aws_iam_policy_document.tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------- storage credential + IAM role ----------

resource "databricks_storage_credential" "this" {
  name            = "${var.name}-credential"
  comment         = "Managed by Terraform. ${var.comment}"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  skip_validation = true
  force_destroy   = var.force_destroy

  aws_iam_role {
    role_arn = local.role_arn
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  aws_account_id        = var.aws_account_id
  role_name             = local.role_name
  external_id           = databricks_storage_credential.this.aws_iam_role[0].external_id
  unity_catalog_iam_arn = databricks_storage_credential.this.aws_iam_role[0].unity_catalog_iam_arn
}

data "databricks_aws_unity_catalog_policy" "this" {
  aws_account_id = var.aws_account_id
  bucket_name    = aws_s3_bucket.this.bucket
  role_name      = local.role_name
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  assume_role_policy   = data.databricks_aws_unity_catalog_assume_role_policy.this.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "${local.role_name}-access"
  role   = aws_iam_role.this.id
  policy = data.databricks_aws_unity_catalog_policy.this.json
}

resource "time_sleep" "iam" {
  create_duration = "30s"
  depends_on      = [aws_iam_role_policy.this, aws_s3_bucket_policy.this]
}

# ---------- external location ----------

resource "databricks_external_location" "this" {
  name            = "${var.name}-location"
  url             = "s3://${aws_s3_bucket.this.bucket}/"
  credential_name = databricks_storage_credential.this.name
  comment         = "Managed by Terraform. ${var.comment}"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  force_destroy   = var.force_destroy

  depends_on = [time_sleep.iam]
}

resource "databricks_grants" "external_location" {
  count             = length(var.location_grants) > 0 ? 1 : 0
  external_location = databricks_external_location.this.id

  dynamic "grant" {
    for_each = var.location_grants
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}
