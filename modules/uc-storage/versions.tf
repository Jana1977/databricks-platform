terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
    # Pass the workspace-level provider (Unity Catalog objects are created through a workspace).
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.90.0, < 2.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }
  }
}
