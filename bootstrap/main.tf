# One-time setup per environment (int, qa), run from a laptop with AWS admin credentials.
# Creates what the GitHub pipeline needs before it can run:
#
#   S3 bucket   <prefix>-<env>-<account>-tfstate   Terraform state for every stack and job repo
#   OIDC        token.actions.githubusercontent.com GitHub Actions can assume AWS roles (once per account)
#   IAM policy  <prefix>-<env>-boundary            ceiling for every role the pipeline creates
#   IAM role    github-<prefix>-<env>-platform     role the platform repo's workflows assume
#
# The pipeline can only create IAM roles named <prefix>-<env>-*, and only with the boundary attached,
# so it cannot give itself or anyone else more access than the boundary allows.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  n    = "${var.name_prefix}-${var.environment}"
  acct = data.aws_caller_identity.current.account_id
  part = data.aws_partition.current.partition

  state_bucket = "${local.n}-${local.acct}-tfstate"
  ci_role_name = "github-${local.n}-platform"

  role_pattern   = "arn:${local.part}:iam::${local.acct}:role/${local.n}-*"
  bucket_pattern = "arn:${local.part}:s3:::${local.n}-*"
  secret_pattern = "arn:${local.part}:secretsmanager:${var.aws_region}:${local.acct}:secret:databricks/${var.environment}/*"
  boundary_arn   = "arn:${local.part}:iam::${local.acct}:policy/${local.n}-boundary"
  oidc_url       = "token.actions.githubusercontent.com"
  oidc_arn       = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${local.part}:iam::${local.acct}:oidc-provider/${local.oidc_url}"
}

# ---------- state bucket ----------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
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

resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------- GitHub OIDC provider (one per AWS account) ----------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------- permissions boundary for every role the pipeline creates ----------

data "aws_iam_policy_document" "boundary" {
  # Databricks cross-account role: launch and manage cluster EC2 instances.
  # The role's own policy narrows this to the workspace VPC and security group.
  statement {
    sid       = "DatabricksCompute"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "SpotServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole", "iam:PutRolePolicy"]
    resources = ["arn:${local.part}:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"]
  }

  # Unity Catalog roles: the platform's own buckets only, and assuming themselves.
  statement {
    sid       = "OwnBuckets"
    actions   = ["s3:*"]
    resources = [local.bucket_pattern, "${local.bucket_pattern}/*"]
  }

  statement {
    sid       = "OwnRoles"
    actions   = ["sts:AssumeRole", "iam:PassRole"]
    resources = [local.role_pattern]
  }

  # Job repo CI roles: read their team's deploy secret.
  statement {
    sid       = "TeamSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [local.secret_pattern]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${local.n}-boundary"
  description = "Permissions boundary for IAM roles created by the Databricks ${var.environment} pipeline"
  policy      = data.aws_iam_policy_document.boundary.json
}

# ---------- CI role for the platform repo ----------

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs that run in the GitHub environment with this name, in the platform repo.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"]
    }
  }
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "Buckets"
    actions   = ["s3:*"]
    resources = [local.bucket_pattern, "${local.bucket_pattern}/*"]
  }

  statement {
    sid = "Network"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # Interface endpoints with private DNS, and flow logs delivered to S3.
  statement {
    sid       = "EndpointDnsAndFlowLogs"
    actions   = ["route53:AssociateVPCWithHostedZone", "logs:CreateLogDelivery", "logs:DeleteLogDelivery"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateRolesOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = [local.role_pattern]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }

  statement {
    sid = "ManageOwnRoles"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.role_pattern]
  }

  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [aws_iam_policy.boundary.arn]
  }

  statement {
    sid = "TeamSecrets"
    actions = [
      "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:GetResourcePolicy",
      "secretsmanager:RestoreSecret",
    ]
    resources = [local.secret_pattern]
  }

  # Never remove a boundary, change the boundary, or touch this CI role or the state bucket's protection.
  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyBoundaryChanges"
    effect    = "Deny"
    actions   = ["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]
    resources = [aws_iam_policy.boundary.arn]
  }

  statement {
    sid       = "DenyStateBucketChanges"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration"]
    resources = [aws_s3_bucket.state.arn]
  }
}

resource "aws_iam_role" "ci" {
  name                 = local.ci_role_name
  description          = "GitHub Actions in ${var.github_org}/${var.github_repo} (environment ${var.environment})"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 7200
}

resource "aws_iam_role_policy" "ci" {
  name   = "${local.ci_role_name}-policy"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
