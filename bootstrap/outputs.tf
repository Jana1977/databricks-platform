output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}

output "boundary_policy_arn" {
  value = aws_iam_policy.boundary.arn
}

output "github_oidc_provider_arn" {
  value = local.oidc_arn
}

output "github_environment_variables" {
  description = "Set these as variables of the GitHub environment named after this environment."
  value = {
    AWS_REGION      = var.aws_region
    AWS_ROLE_ARN    = aws_iam_role.ci.arn
    TF_STATE_BUCKET = aws_s3_bucket.state.bucket
  }
}
