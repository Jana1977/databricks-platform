output "workspace_id" {
  value = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "https://... URL of the workspace."
  value       = databricks_mws_workspaces.this.workspace_url
}

output "cross_account_role_arn" {
  value = aws_iam_role.crossaccount.arn
}

output "root_bucket" {
  value = aws_s3_bucket.root.bucket
}
