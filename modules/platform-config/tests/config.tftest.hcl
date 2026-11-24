# Offline test of config parsing and the checks that catch typos.

variables {
  environment = "int"
  teams_dir   = "./tests/teams"
}

run "good_config" {
  command = plan

  variables {
    config_raw = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
    config = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
  }

  assert {
    condition     = output.names.name == "dbx-int" && output.names.workspace_name == "dbx-int"
    error_message = "Default prefix dbx and workspace name dbx-int expected."
  }

  assert {
    condition     = keys(output.teams) == ["alpha"]
    error_message = "Only teams whose environments include int (alpha), not beta (qa only) or _ignored."
  }

  assert {
    condition     = output.config.network.nat_gateway_count == 1 && output.config.safety.allow_destroy_data == false
    error_message = "Defaults not applied."
  }
}

run "typo_in_config_key_fails" {
  command = plan

  variables {
    config_raw = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"], nat_gatway_count = 2 }
    }
    config = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
  }

  expect_failures = [terraform_data.checks]
}

run "wrong_environment_in_file_fails" {
  command = plan

  variables {
    config_raw = {
      environment = "qa"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
    config = {
      environment = "qa"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
  }

  expect_failures = [terraform_data.checks]
}

run "typo_in_team_file_fails" {
  command = plan

  variables {
    teams_dir = "./tests/teams-bad"
    config_raw = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
    config = {
      environment = "int"
      aws         = { account_id = "111111111111", region = "us-east-1" }
      databricks  = { account_id = "00000000-0000-0000-0000-000000000000", admins = ["a@example.com"] }
      network     = { vpc_cidr = "10.20.0.0/16", private_subnet_cidrs = ["10.20.0.0/19", "10.20.32.0/19"], public_subnet_cidrs = ["10.20.64.0/24"] }
    }
  }

  expect_failures = [terraform_data.checks]
}
