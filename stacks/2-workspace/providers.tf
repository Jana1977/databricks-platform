terraform {
  required_version = ">= 1.10.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
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

provider "aws" {
  region = local.c.aws.region

  default_tags {
    tags = local.tags
  }
}

# Workspace-level Databricks API for the workspace stack 1 created.
provider "databricks" {
  host      = local.infra.workspace_url
  auth_type = "oauth-m2m"
}
