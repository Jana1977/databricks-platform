# Offline test of the team module: no AWS or Databricks calls (mocked providers).
#   terraform -chdir=modules/team init -backend=false && terraform -chdir=modules/team test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "time" {}

mock_provider "databricks" {
  alias = "account"
  # Workspace assignments need numeric principal IDs.
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

variables {
  environment              = "int"
  name_prefix              = "dbx"
  aws_account_id           = "111111111111"
  region                   = "us-east-1"
  databricks_account_id    = "00000000-0000-0000-0000-000000000000"
  workspace_id             = "1234567890"
  workspace_url            = "https://dbc-test.cloud.databricks.com"
  admins_group_name        = "dbx-int-platform-admins"
  state_bucket             = "dbx-int-111111111111-tfstate"
  github_oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/dbx-int-boundary"

  team = {
    name               = "cpps"
    environments       = ["int"]
    managers           = ["lead@example.com"]
    members            = ["eng@example.com"]
    groups             = { analysts = ["analyst@example.com"] }
    service_principals = ["reporting"]
    job_repos          = ["my-org/databricks-jobs"]
    budget             = { monthly_usd = 500 }
  }
}

run "creates_the_full_team" {
  command = apply

  providers = {
    aws                  = aws
    time                 = time
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  assert {
    condition     = toset([for g in databricks_group.this : g.display_name]) == toset(["dbx-int-cpps-users", "dbx-int-cpps-managers", "dbx-int-cpps-analysts"])
    error_message = "Expected users, managers and analysts groups."
  }

  assert {
    condition     = length(databricks_group_member.user) == 5
    error_message = "users(3) + managers(1) + analysts(1) memberships expected."
  }

  assert {
    condition     = toset([for s in databricks_service_principal.this : s.display_name]) == toset(["dbx-int-cpps-deploy", "dbx-int-cpps-reporting"])
    error_message = "Expected deploy and reporting service principals."
  }

  assert {
    condition     = length(databricks_mws_permission_assignment.group) == 3 && length(databricks_mws_permission_assignment.service_principal) == 2
    error_message = "Every group and service principal must be assigned to the workspace."
  }

  assert {
    condition     = databricks_catalog.this.name == "int_cpps" && databricks_catalog.this.isolation_mode == "ISOLATED"
    error_message = "Catalog must be int_cpps and bound to this workspace."
  }

  assert {
    condition     = databricks_catalog.this.storage_root == "s3://dbx-int-cpps-111111111111/managed"
    error_message = "Catalog storage must be in the team bucket."
  }

  assert {
    condition     = toset(keys(databricks_schema.this)) == toset(["raw", "curated"])
    error_message = "Default schemas raw and curated expected."
  }

  assert {
    condition     = databricks_cluster_policy.job.name == "cpps-job-policy" && jsondecode(databricks_cluster_policy.job.definition)["custom_tags.team"].value == "cpps"
    error_message = "Job policy must be named cpps-job-policy and force the team tag."
  }

  assert {
    condition     = jsondecode(databricks_cluster_policy.job.definition)["num_workers"].maxValue == 4
    error_message = "Default max_workers is 4."
  }

  assert {
    condition     = databricks_sql_endpoint.this[0].name == "cpps-warehouse"
    error_message = "Warehouse expected."
  }

  assert {
    condition     = databricks_directory.team.path == "/Teams/cpps"
    error_message = "Team folder must be /Teams/cpps."
  }

  assert {
    condition     = aws_secretsmanager_secret.deploy.name == "databricks/int/teams/cpps/deploy-sp"
    error_message = "Deploy secret name is part of the hand-off contract."
  }

  assert {
    condition     = aws_iam_role.jobs_ci[0].name == "dbx-int-cpps-jobs-ci"
    error_message = "Job repo CI role expected."
  }

  assert {
    condition     = length(databricks_budget.this) == 1
    error_message = "Budget expected when monthly_usd > 0."
  }

  assert {
    condition     = output.handoff.variables.DEPLOY_SECRET_ID == "databricks/int/teams/cpps/deploy-sp" && output.handoff.variables.TEAM == "cpps"
    error_message = "Hand-off variables wrong."
  }
}

run "minimal_team_has_no_ci_role_or_budget" {
  command = plan

  providers = {
    aws                  = aws
    time                 = time
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  variables {
    team = {
      name     = "mini"
      managers = ["lead@example.com"]
      sql_warehouse = {
        enabled = false
      }
      compute = {
        allow_interactive = false
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.jobs_ci) == 0 && length(databricks_budget.this) == 0
    error_message = "No job repos = no CI role; no budget = no budget alert."
  }

  assert {
    condition     = length(databricks_sql_endpoint.this) == 0 && length(databricks_cluster_policy.interactive) == 0
    error_message = "Warehouse and interactive policy are optional."
  }
}

run "rejects_bad_team_name" {
  command = plan

  providers = {
    aws                  = aws
    time                 = time
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  variables {
    team = {
      name     = "Bad-Name"
      managers = ["lead@example.com"]
    }
  }

  expect_failures = [var.team]
}

run "rejects_non_email_member" {
  command = plan

  providers = {
    aws                  = aws
    time                 = time
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  variables {
    team = {
      name     = "cpps"
      managers = ["not-an-email"]
    }
  }

  expect_failures = [var.team]
}
