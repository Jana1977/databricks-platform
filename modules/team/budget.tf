# Monthly spend alert for clusters and warehouses tagged team=<team> in this workspace.

resource "databricks_budget" "this" {
  provider     = databricks.account
  count        = local.team.budget.monthly_usd > 0 ? 1 : 0
  display_name = local.p

  alert_configurations {
    time_period        = "MONTH"
    trigger_type       = "CUMULATIVE_SPENDING_EXCEEDED"
    quantity_type      = "LIST_PRICE_DOLLARS_USD"
    quantity_threshold = tostring(local.team.budget.monthly_usd)

    dynamic "action_configurations" {
      for_each = toset(local.budget_emails)
      content {
        action_type = "EMAIL_NOTIFICATION"
        target      = action_configurations.value
      }
    }
  }

  filter {
    workspace_id {
      operator = "IN"
      values   = [tonumber(var.workspace_id)]
    }

    tags {
      key = "team"
      value {
        operator = "IN"
        values   = [local.team.name]
      }
    }
  }
}
