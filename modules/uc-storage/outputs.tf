output "bucket" {
  value = aws_s3_bucket.this.bucket
}

output "url" {
  description = "s3:// URL of the bucket root."
  value       = databricks_external_location.this.url
}

output "external_location_name" {
  value = databricks_external_location.this.name
}

output "storage_credential_name" {
  value = databricks_storage_credential.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
