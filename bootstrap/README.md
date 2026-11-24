# bootstrap

Run once per environment, from a laptop with admin credentials for that AWS account. It creates what the GitHub workflows need before they can run.

| Resource | Name | Why |
|---|---|---|
| S3 bucket | `<prefix>-<env>-<account>-tfstate` | Terraform state for all stacks and job repos (versioned, encrypted, private, TLS only, `prevent_destroy`) |
| IAM OIDC provider | `token.actions.githubusercontent.com` | GitHub Actions log in to AWS without stored keys (one per AWS account) |
| IAM policy | `<prefix>-<env>-boundary` | Permissions boundary on every role the pipeline creates |
| IAM role | `github-<prefix>-<env>-platform` | Assumed by the platform repo's workflows in GitHub environment `<env>` |

## int

```bash
cp int.tfvars.example int.tfvars      # set github_org
terraform init
terraform apply -var-file=int.tfvars
terraform output github_environment_variables
```

Put `AWS_ROLE_ARN`, `AWS_REGION` and `TF_STATE_BUCKET` into the platform repo's GitHub environment `int`.

## qa

```bash
cp qa.tfvars.example qa.tfvars        # create_github_oidc_provider = false if qa shares int's AWS account
terraform workspace new qa            # separate local state for qa
terraform apply -var-file=qa.tfvars
```

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `environment` | (required) | `int` or `qa` |
| `aws_region` | (required) | Region of the state bucket (same as `aws.region` in `config/<env>.yaml`) |
| `github_org` | (required) | Owner of the platform repo, exact case |
| `github_repo` | `databricks-platform` | Platform repo name |
| `name_prefix` | `dbx` | Same as `name_prefix` in `config/<env>.yaml` |
| `create_github_oidc_provider` | `true` | `false` if the account already has GitHub's OIDC provider |

## State of this folder

The state is local (`terraform.tfstate`, git-ignored) because this folder creates the bucket everything else uses. Keep it safe, or move it into the bucket after the first apply:

1. Add `backend "s3" {}` inside the `terraform` block in `versions.tf`.
2. Run:
   ```bash
   terraform init -migrate-state \
     -backend-config="bucket=<TF_STATE_BUCKET>" \
     -backend-config="key=bootstrap/int.tfstate" \
     -backend-config="region=<region>" \
     -backend-config="use_lockfile=true"
   ```

## What the CI role may do

- S3: buckets named `<prefix>-<env>-*` only (and it cannot delete the state bucket or change its policy, versioning or lifecycle).
- EC2: VPC, subnet, route, gateway, address, security group, VPC endpoint and flow log actions, in this region only.
- IAM: create roles named `<prefix>-<env>-*` only with the boundary attached; manage their inline policies. It cannot remove a boundary, change the boundary policy, or edit its own role.
- Secrets Manager: secrets under `databricks/<env>/` only.
