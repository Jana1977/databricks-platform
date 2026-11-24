# Everything one team needs in one environment.
#
#   identity.tf       account groups, members, service principals, workspace access, OAuth secret
#   aws.tf            Secrets Manager secret + IAM role for the team's job repo CI
#   unity_catalog.tf  team bucket, storage credential, external location, catalog, schemas, grants
#   compute.tf        cluster policies and the SQL warehouse
#   workspace.tf      team folder, secret scope, entitlements
#   budget.tf         monthly budget alert
#
# Naming (prefix = <name_prefix>-<env>-<team>, for example dbx-int-cpps):
#   account groups      <prefix>-users, <prefix>-managers, <prefix>-<group>
#   service principals  <prefix>-deploy, <prefix>-<sp>
#   catalog             <env>_<team>           (int_cpps)
#   workspace objects   <team>-job-policy, <team>-interactive-policy, <team>-warehouse,
#                       secret scope <team>, folder /Teams/<team>

locals {
  team = var.team
  p    = "${var.name_prefix}-${var.environment}-${local.team.name}"

  catalog      = "${var.environment}_${local.team.name}"
  folder       = "${var.teams_folder}/${local.team.name}"
  state_prefix = "jobs/${var.environment}/${local.team.name}/"
  secret_name  = "databricks/${var.environment}/teams/${local.team.name}/deploy-sp"

  all_users = toset(distinct(concat(local.team.managers, local.team.members, flatten(values(local.team.groups)))))

  groups = merge(
    {
      users    = { name = "${local.p}-users", members = local.all_users }
      managers = { name = "${local.p}-managers", members = toset(local.team.managers) }
    },
    { for g, m in local.team.groups : g => { name = "${local.p}-${g}", members = toset(m) } }
  )

  memberships = merge([
    for gk, g in local.groups : { for u in g.members : "${gk}|${u}" => { group = gk, user = u } }
  ]...)

  service_principals = merge(
    { deploy = "${local.p}-deploy" },
    { for s in local.team.service_principals : s => "${local.p}-${s}" }
  )

  users_group    = local.groups.users.name
  managers_group = local.groups.managers.name

  budget_emails = length(local.team.budget.alert_emails) > 0 ? local.team.budget.alert_emails : local.team.managers

  tags = merge(var.tags, { team = local.team.name })
}
