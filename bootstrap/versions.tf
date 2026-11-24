terraform {
  required_version = ">= 1.10.0"

  # Local state on purpose: this creates the bucket the other stacks keep their state in.
  # Keep bootstrap/terraform.tfstate safe (or move it into the bucket afterwards, see README.md).

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment = var.environment
      platform    = "databricks"
      managed_by  = "terraform-bootstrap"
    }
  }
}
