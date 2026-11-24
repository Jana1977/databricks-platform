# Offline plan of stack 2 (mocked providers, stack 1 outputs faked).

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "time" {}

mock_provider "databricks" {
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
}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      workspace_id  = 1234567890
      workspace_url = "https://dbc-test.cloud.databricks.com"
      admins_group  = "dbx-int-platform-admins"
    }
  }
}

run "int_plans" {
  command = apply

  variables {
    environment  = "int"
    state_bucket = "dbx-int-111111111111-tfstate"
  }

  assert {
    condition     = output.teams_folder == "/Teams"
    error_message = "Teams parent folder expected."
  }

  assert {
    condition     = output.platform_catalog == "int_platform"
    error_message = "Platform catalog int_platform expected."
  }

  assert {
    condition     = databricks_catalog.platform[0].storage_root == "s3://dbx-int-platform-111111111111/managed"
    error_message = "Platform catalog stored in its own bucket."
  }
}
