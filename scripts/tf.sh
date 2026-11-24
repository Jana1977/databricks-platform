#!/usr/bin/env bash
# Run one platform stack for one environment. Used by the GitHub workflows and for local runs.
#
#   scripts/tf.sh <action> <env> <stack>
#
#   action  plan            plan; writes .plans/<env>-<stack>.txt; exit 0 also when there are changes
#           apply           plan, then apply that plan
#           destroy         destroy everything in the stack
#           output          print the stack outputs as JSON
#           wait-workspace  wait until the workspace URL from 1-infra answers (new workspaces take a few minutes)
#   env     int | qa        (config/<env>.yaml must exist)
#   stack   1-infra | 2-workspace | 3-teams
#
# Needs: terraform, aws CLI, and these environment variables
#   TF_STATE_BUCKET            state bucket from bootstrap
#   AWS_REGION                 region of the state bucket
#   DATABRICKS_CLIENT_ID       CI service principal (account admin)
#   DATABRICKS_CLIENT_SECRET
#   AWS credentials            (in CI from OIDC; locally from your profile)
set -euo pipefail

ACTION="${1:?usage: tf.sh <plan|apply|destroy|output|wait-workspace> <env> <stack>}"
ENV_NAME="${2:?environment missing (int or qa)}"
STACK="${3:?stack missing (1-infra, 2-workspace, 3-teams)}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/stacks/$STACK"
PLANS="$ROOT/.plans"

[[ -d "$DIR" ]] || { echo "Unknown stack '$STACK'. Use 1-infra, 2-workspace or 3-teams." >&2; exit 2; }
[[ -f "$ROOT/config/$ENV_NAME.yaml" ]] || { echo "config/$ENV_NAME.yaml not found." >&2; exit 2; }
: "${TF_STATE_BUCKET:?Set TF_STATE_BUCKET (bootstrap output state_bucket)}"
: "${AWS_REGION:?Set AWS_REGION}"

export TF_IN_AUTOMATION=1
export TF_INPUT=0
export TF_VAR_environment="$ENV_NAME"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
export TF_VAR_ci_client_id="${DATABRICKS_CLIENT_ID:-}"

state_key() { echo "platform/$ENV_NAME/$1.tfstate"; }

state_exists() {
  aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$(state_key "$1")" >/dev/null 2>&1
}

tf() { terraform -chdir="$DIR" "$@"; }

init() {
  echo "::group::terraform init ($ENV_NAME/$STACK)"
  tf init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$(state_key "$STACK")" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="encrypt=true" \
    -backend-config="use_lockfile=true"
  echo "::endgroup::"
}

# Stacks 2 and 3 read outputs of the stacks before them. On a brand-new environment those
# do not exist yet, so a plan is skipped (the deploy workflow applies the stacks in order).
previous_stacks_ready() {
  case "$STACK" in
    1-infra) return 0 ;;
    2-workspace) state_exists 1-infra ;;
    3-teams) state_exists 1-infra && state_exists 2-workspace ;;
  esac
}

gh_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1=$2" >>"$GITHUB_OUTPUT"; fi
}

do_plan() {
  mkdir -p "$PLANS"
  local out="$PLANS/$ENV_NAME-$STACK.txt"
  if ! previous_stacks_ready; then
    echo "Skipped: apply the earlier stacks first (state for them does not exist yet)." | tee "$out"
    gh_output changes skipped
    return 0
  fi
  init
  set +e
  tf plan -input=false -lock-timeout=5m -out=tfplan -detailed-exitcode
  local rc=$?
  set -e
  case $rc in
    0) gh_output changes false ;;
    2) gh_output changes true ;;
    *) echo "terraform plan failed for $ENV_NAME/$STACK" >&2; exit $rc ;;
  esac
  tf show -no-color tfplan >"$out"
  grep -E '^(Plan:|No changes\.)' "$out" || true
  return 0
}

case "$ACTION" in
  plan)
    do_plan
    ;;
  apply)
    if ! previous_stacks_ready; then
      echo "Cannot apply $STACK: apply the earlier stacks first." >&2
      exit 1
    fi
    do_plan
    tf apply -input=false -lock-timeout=5m tfplan
    ;;
  destroy)
    if ! state_exists "$STACK"; then
      echo "Nothing to destroy: no state for $ENV_NAME/$STACK."
      exit 0
    fi
    init
    tf destroy -input=false -lock-timeout=5m -auto-approve
    ;;
  output)
    init >/dev/null
    tf output -json
    ;;
  wait-workspace)
    STACK=1-infra
    DIR="$ROOT/stacks/1-infra"
    init >/dev/null
    url="$(tf output -raw workspace_url)"
    echo "Waiting for $url ..."
    for _ in $(seq 1 60); do
      code="$(curl -s -o /dev/null -w '%{http_code}' "$url/api/2.0/clusters/spark-versions" || true)"
      # 401/403 = the workspace answers (no token sent); anything else = not ready yet.
      if [[ "$code" == "401" || "$code" == "403" || "$code" == "200" ]]; then
        echo "Workspace is up (HTTP $code)."
        exit 0
      fi
      sleep 10
    done
    echo "Workspace did not answer within 10 minutes." >&2
    exit 1
    ;;
  *)
    echo "Unknown action '$ACTION'." >&2
    exit 2
    ;;
esac
