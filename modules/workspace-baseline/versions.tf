terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # Pass the workspace-level provider.
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.90.0, < 2.0.0"
    }
  }
}
