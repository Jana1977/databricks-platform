# Offline plan of stack 3 with the real teams/*.yaml files (mocked providers, stacks 1-2 outputs faked).

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "time" {}

mock_provider "databricks" {
  alias = "account"
  mock_resource "databricks_group" {
    defaults = { id = "1001" }
  }
  mock_resource "databricks_service_principal" {
    defaults = { id = "2001", application_id = "00000000-aaaa-bbbb-cccc-000000000001" }
  }
}

mock_provider "databricks" {
  alias = "workspace"
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

override_data {
  target = data.terraform_remote_state.workspace
  values = {
    outputs = {
      teams_folder = "/Teams"
    }
  }
}

run "int_has_team_cpps" {
  command = apply

  variables {
    environment  = "int"
    state_bucket = "dbx-int-111111111111-tfstate"
  }

  assert {
    condition     = keys(module.team) == ["cpps"]
    error_message = "teams/cpps.yaml lists int, so int must have exactly team cpps."
  }

  assert {
    condition     = output.teams["cpps"].catalog == "int_cpps" && output.teams["cpps"].job_policy == "cpps-job-policy"
    error_message = "Team objects named after the team and environment."
  }

  assert {
    condition     = output.team_handoff["cpps"].variables.TF_STATE_BUCKET == "dbx-int-111111111111-tfstate"
    error_message = "Hand-off must carry the state bucket."
  }
}

run "qa_has_no_teams_yet" {
  command = plan

  variables {
    environment  = "qa"
    state_bucket = "dbx-qa-222222222222-tfstate"
  }

  assert {
    condition     = length(module.team) == 0
    error_message = "No team file lists qa yet."
  }
}
