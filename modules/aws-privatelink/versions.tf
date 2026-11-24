terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
    # Pass the account-level provider (host = https://accounts.cloud.databricks.com).
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.90.0, < 2.0.0"
    }
  }
}
