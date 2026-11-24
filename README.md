# databricks-platform

Terraform + GitHub Actions that build a Databricks workspace on AWS and onboard teams from YAML files.
Environments: **int** (deployed on every merge to `main`) and **qa** (deployed by hand).

Its partner repo is **databricks-jobs** (each team's jobs). The full click-through guide for both repos is [docs/SETUP-GUIDE.html](docs/SETUP-GUIDE.html).

## Layout

```
bootstrap/                 one-time per environment, from a laptop: state bucket, GitHub OIDC, CI role, boundary
config/int.yaml, qa.yaml   platform settings per environment (not secret)
teams/_template.yaml       copy to teams/<team>.yaml to onboard a team
teams/cpps.yaml            example team
modules/
  platform-config/         reads and checks the YAML files (typos stop the plan)
  aws-network/             VPC, subnets, NAT, S3 endpoint, Databricks security group, flow logs
  aws-privatelink/         optional back-end (and front-end) PrivateLink + private access settings
  databricks-workspace/    cross-account role, root bucket, credentials, storage, network, workspace
  uc-storage/              bucket + IAM role + storage credential + external location
  workspace-baseline/      workspace settings, users entitlements, /Teams folder
  team/                    everything for one team in one environment
stacks/
  1-infra/                 network + workspace + metastore assignment + platform admins
  2-workspace/             baseline settings + <env>_platform catalog
  3-teams/                 module "team" for each teams/*.yaml listing this environment
scripts/
  tf.sh                    plan/apply/destroy one stack (used by CI and locally)
  handoff.sh               prints the per-team variables for job repos
  check.sh                 offline validate + terraform test
.github/workflows/
  platform-ci.yml          PR: fmt, validate, tests, plan, PR comment
  platform-deploy.yml      push to main -> int; manual -> int or qa
  platform-destroy.yml     manual teardown
```

Each stack has its own state: `s3://<TF_STATE_BUCKET>/platform/<env>/<stack>.tfstate`.

## Set up (int)

1. **Bootstrap AWS** (admin credentials for the int account):
   ```bash
   cd bootstrap && cp int.tfvars.example int.tfvars   # set github_org
   terraform init && terraform apply -var-file=int.tfvars
   terraform output github_environment_variables
   ```
2. **Databricks account console:** create service principal `databricks-platform-ci`, make it **Account admin**, generate an **OAuth secret**. With an existing metastore, make it (or a group it is in) **Metastore admin**.
3. **GitHub:** Settings > Environments > `int` (no branch restriction):
   - variables `AWS_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET` (bootstrap output)
   - secrets `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`
4. **Edit** `config/int.yaml` (AWS account, region, Databricks account ID, admins), `teams/cpps.yaml` (e-mails, `job_repos`), `.github/CODEOWNERS`.
5. **Push to `main`.** `platform-deploy` applies `1-infra`, waits for the workspace, applies `2-workspace` and `3-teams`. The run summary shows the workspace URL and the **job repo hand-off** (7 variables per team).
6. **Protect `main`:** require PRs, Code Owner review, and the checks `fmt, validate, test` and `plan (int)`.

## Onboard a team

1. Copy `teams/_template.yaml` to `teams/<team>.yaml`. Set `name`, `environments: [int]`, `managers`, `members`, `job_repos`, compute limits.
2. Open a PR. `platform-ci` comments the plan (46 resources for a team made from the template; more with extra groups, service principals or a budget).
3. A platform admin approves; merge. `platform-deploy` creates the team in int.
4. Give the team the hand-off variables from the run summary for their jobs repo.

## Add qa

Bootstrap qa (`qa.tfvars`; `create_github_oidc_provider = false` if it shares int's AWS account), create GitHub environment `qa` (required reviewers, branch `main` only), edit `config/qa.yaml`, add `qa` to teams' `environments`, then **Actions > platform-deploy > Run workflow > qa**.

## `config/<env>.yaml`

| Key | Default | Meaning |
|---|---|---|
| `environment` | (required) | Must equal the file name |
| `name_prefix` | `dbx` | Prefix of AWS and account-level names |
| `aws.account_id`, `aws.region` | (required) | Target AWS account (checked against the credentials) and region |
| `databricks.account_id` | (required) | Databricks account ID |
| `databricks.workspace_name` | `<prefix>-<env>` | |
| `databricks.admins` | (required) | E-mails for `<prefix>-<env>-platform-admins` |
| `databricks.create_users` | `false` | Create missing users (sandbox only) |
| `unity_catalog.metastore_id` | `""` = region's metastore | |
| `unity_catalog.create_metastore` | `false` | Only if the region has none |
| `unity_catalog.assign_metastore` | `true` | `false` if the workspace was auto-attached |
| `unity_catalog.platform_catalog` | `true` | Create `<env>_platform` |
| `network.vpc_cidr`, `private_subnet_cidrs` (2+, /17-/26), `public_subnet_cidrs` | (required) | |
| `network.availability_zones` | first N zones | |
| `network.nat_gateway_count` | `1` | |
| `network.interface_endpoints` | `false` | STS + Kinesis endpoints |
| `network.flow_logs` | `false` | VPC flow logs to S3 |
| `network.privatelink.*` | off | `enabled`, `subnet_cidrs`, `public_access_enabled`, `workspace_service`, `relay_service`, `frontend.{vpc_id,subnet_ids,allowed_cidrs}` |
| `workspace.token_max_lifetime_days` | `90` | |
| `workspace.ip_allow_list` | `[]` | Include CI egress IPs |
| `workspace.restrict_workspace_admins` | `true` | |
| `workspace.disable_legacy_features` | `true` | |
| `safety.allow_destroy_data` | `false` | `true` in int only |
| `tags` | `{}` | |

## `teams/<team>.yaml`

| Key | Default | Meaning |
|---|---|---|
| `name` | (required) | = file name, 2-20 lower-case letters/digits |
| `environments` | (required) | `[int]`, `[int, qa]` |
| `managers` | (required) | Team admins (e-mails) |
| `members` | `[]` | Everyone else |
| `groups` | `{}` | `name: [emails]` extra groups |
| `service_principals` | `[]` | Extra read-only service principals |
| `job_repos` | `[]` | `org/repo` allowed to deploy the team's jobs |
| `compute.node_types` | `[m5d.large, m5d.xlarge]` | Allowed EC2 types |
| `compute.max_workers` | `4` | |
| `compute.allow_interactive` | `true` | Notebook cluster policy |
| `compute.autotermination_minutes` | `30` | |
| `compute.max_clusters_per_user` | `2` | |
| `sql_warehouse.enabled`, `size`, `auto_stop_minutes`, `max_clusters`, `serverless` | `true`, `2X-Small`, `10`, `1`, `false` | |
| `catalog.schemas` | `[raw, curated]` | |
| `secret_scope` | `true` | |
| `budget.monthly_usd`, `alert_emails` | `0` (off), managers | |

## Local runs

```bash
export AWS_REGION=us-east-1 TF_STATE_BUCKET=<bucket> DATABRICKS_CLIENT_ID=... DATABRICKS_CLIENT_SECRET=...
scripts/check.sh                   # offline checks, no cloud access
scripts/tf.sh plan int 1-infra     # 1-infra | 2-workspace | 3-teams
scripts/tf.sh apply int 3-teams
scripts/handoff.sh int
```

## Security notes

- GitHub logs in to AWS with OIDC; the CI role trusts only this repo's `<env>` environment.
- Every IAM role the pipeline creates is named `<prefix>-<env>-*` and carries the boundary `<prefix>-<env>-boundary`; the CI role cannot remove or change the boundary or edit itself.
- The Databricks CI service principal is an account admin. Keep write access to this repo to the platform team and protect `main`.

See [docs/SETUP-GUIDE.html](docs/SETUP-GUIDE.html) for troubleshooting and the full parameter reference.
