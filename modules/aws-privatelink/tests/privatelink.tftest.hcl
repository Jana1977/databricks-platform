# Offline test: endpoint service names per region, and a clear error for unknown regions.

mock_provider "aws" {}
mock_provider "databricks" {}

variables {
  name                      = "dbx-int"
  databricks_account_id     = "00000000-0000-0000-0000-000000000000"
  vpc_id                    = "vpc-123"
  availability_zones        = ["us-east-1a", "us-east-1b"]
  subnet_cidrs              = ["10.20.66.0/27", "10.20.66.32/27"]
  compute_security_group_id = "sg-123"
}

run "us_east_1_uses_built_in_services" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = aws_vpc_endpoint.rest.service_name == "com.amazonaws.vpce.us-east-1.vpce-svc-09143d1e626de2f04"
    error_message = "REST endpoint service for us-east-1."
  }

  assert {
    condition     = aws_vpc_endpoint.relay.service_name == "com.amazonaws.vpce.us-east-1.vpce-svc-00018a8c3ff62ffdf"
    error_message = "Relay endpoint service for us-east-1."
  }

  assert {
    condition     = length(aws_vpc_endpoint.frontend) == 0
    error_message = "No front-end endpoint unless frontend.vpc_id is set."
  }
}

run "unknown_region_needs_override" {
  command = plan

  variables {
    region = "eu-west-1"
  }

  expect_failures = [terraform_data.service_names]
}
