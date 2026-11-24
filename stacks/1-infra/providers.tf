terraform {
  required_version = ">= 1.10.0"

  # Partial config: scripts/tf.sh passes bucket, key, region and use_lockfile.
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

# Account-level Databricks API. Credentials come from DATABRICKS_CLIENT_ID / DATABRICKS_CLIENT_SECRET.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = local.c.databricks.account_id
  auth_type  = "oauth-m2m"
}
