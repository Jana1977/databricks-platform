# Offline plan of stack 1 with the real config/int.yaml and config/qa.yaml (mocked providers).

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }
}

mock_provider "time" {}

mock_provider "databricks" {
  alias = "account"
  mock_data "databricks_aws_unity_catalog_assume_role_policy" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "databricks_aws_unity_catalog_policy" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "databricks_aws_assume_role_policy" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "databricks_aws_crossaccount_policy" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "databricks_aws_bucket_policy" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "databricks_group" {
    defaults = { id = "1001" }
  }
  mock_resource "databricks_mws_workspaces" {
    defaults = { workspace_id = 1234567890, workspace_url = "https://dbc-test.cloud.databricks.com" }
  }
  mock_data "databricks_metastore" {
    defaults = { metastore_id = "11111111-2222-3333-4444-555555555555" }
  }
}

run "int_plans" {
  command = apply

  variables {
    environment  = "int"
    ci_client_id = "00000000-aaaa-bbbb-cccc-000000000001"
  }

  assert {
    condition     = module.network.vpc_cidr == "10.20.0.0/16" && length(module.network.private_subnet_ids) == 2
    error_message = "int network from config/int.yaml expected."
  }

  assert {
    condition     = length(module.privatelink) == 0
    error_message = "PrivateLink is off in int."
  }

  assert {
    condition     = output.metastore_id == "11111111-2222-3333-4444-555555555555"
    error_message = "Empty metastore_id must use the region's existing metastore."
  }

  assert {
    condition     = output.admins_group == "dbx-int-platform-admins"
    error_message = "Admins group name."
  }

  assert {
    condition     = length(databricks_group_member.ci) == 1
    error_message = "The CI service principal joins the admins group."
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "Flow logs are off in int."
  }
}

run "wrong_aws_account_is_rejected" {
  command = plan

  variables {
    environment = "qa" # qa.yaml says 222222222222, the mocked caller is 111111111111
  }

  expect_failures = [terraform_data.aws_account_guard]
}

run "all_optional_features" {
  command = apply

  variables {
    environment = "int"
    config_dir  = "./tests/fixtures"
  }

  assert {
    condition     = length(module.privatelink) == 1
    error_message = "PrivateLink module expected."
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 1
    error_message = "Flow-log bucket expected."
  }

  assert {
    condition     = length(databricks_metastore.this) == 1 && length(data.databricks_metastore.region) == 0
    error_message = "create_metastore creates one instead of looking it up."
  }

  assert {
    condition     = length(databricks_user.admin) == 1 && length(data.databricks_user.admin) == 0
    error_message = "create_users creates the admin user."
  }

  assert {
    condition     = module.workspace.workspace_id == 1234567890
    error_message = "Workspace created."
  }
}
