# ---------- deploy credentials in Secrets Manager ----------
# The job repo's CI reads this secret instead of storing a Databricks secret in GitHub.

resource "aws_secretsmanager_secret" "deploy" {
  name                    = local.secret_name
  description             = "OAuth client for ${databricks_service_principal.this["deploy"].display_name} (Databricks ${var.environment}, team ${local.team.name})"
  recovery_window_in_days = var.force_destroy ? 0 : 7
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "deploy" {
  secret_id = aws_secretsmanager_secret.deploy.id
  secret_string = jsonencode({
    client_id     = databricks_service_principal.this["deploy"].application_id
    client_secret = databricks_service_principal_secret.deploy.secret
    host          = var.workspace_url
  })
}

# ---------- IAM role for the team's job repos (GitHub OIDC) ----------

data "aws_iam_policy_document" "jobs_ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflow jobs that run in the GitHub environment named like this environment.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in local.team.job_repos : "repo:${r}:environment:${var.environment}"]
    }
  }
}

data "aws_iam_policy_document" "jobs_ci" {
  statement {
    sid       = "ListOwnStatePrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.state_prefix}*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.state_prefix}*"]
  }

  statement {
    sid       = "ReadDeploySecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.deploy.arn]
  }
}

resource "aws_iam_role" "jobs_ci" {
  count                = length(local.team.job_repos) > 0 ? 1 : 0
  name                 = "${local.p}-jobs-ci"
  description          = "GitHub Actions in ${join(", ", local.team.job_repos)} deploy jobs for team ${local.team.name} (${var.environment})"
  assume_role_policy   = data.aws_iam_policy_document.jobs_ci_trust.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = local.tags
}

resource "aws_iam_role_policy" "jobs_ci" {
  count  = length(aws_iam_role.jobs_ci)
  name   = "${local.p}-jobs-ci"
  role   = aws_iam_role.jobs_ci[0].id
  policy = data.aws_iam_policy_document.jobs_ci.json
}
