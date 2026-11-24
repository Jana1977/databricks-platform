#!/usr/bin/env bash
# Prints a Markdown summary of an environment: workspace URL and, per team, the GitHub
# environment variables its job repo needs (with ready-to-run `gh` commands).
#
#   scripts/handoff.sh <env>          (same environment variables as scripts/tf.sh)
set -euo pipefail

ENV_NAME="${1:?environment missing (int or qa)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

has_state() {
  aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "platform/$ENV_NAME/$1.tfstate" >/dev/null 2>&1
}

echo "## Databricks platform: \`$ENV_NAME\`"
echo

if ! has_state 1-infra; then
  echo "1-infra has not been applied yet."
  exit 0
fi

infra="$("$ROOT/scripts/tf.sh" output "$ENV_NAME" 1-infra)"
url="$(jq -r '.workspace_url.value' <<<"$infra")"
echo "| | |"
echo "|---|---|"
echo "| Workspace | <$url> |"
echo "| Workspace ID | \`$(jq -r '.workspace_id.value' <<<"$infra")\` |"
echo "| Metastore | \`$(jq -r '.metastore_id.value' <<<"$infra")\` |"
echo "| Admins group | \`$(jq -r '.admins_group.value' <<<"$infra")\` |"
echo "| Cluster outbound IPs | \`$(jq -r '.nat_public_ips.value | join(", ")' <<<"$infra")\` |"
echo

if ! has_state 3-teams; then
  echo "3-teams has not been applied yet."
  exit 0
fi

teams="$("$ROOT/scripts/tf.sh" output "$ENV_NAME" 3-teams)"
count="$(jq '.team_handoff.value | length' <<<"$teams")"
if [[ "$count" == "0" ]]; then
  echo "No teams in \`$ENV_NAME\` yet. Add teams/<team>.yaml with \`environments: [$ENV_NAME]\`."
  exit 0
fi

echo "## Job repo hand-off"
echo
echo "In each job repo: **Settings > Environments > New environment** named \`$ENV_NAME\`, then add these **variables**"
echo "(no secrets needed: the job repo reads its Databricks credentials from AWS Secrets Manager)."
echo

jq -r --arg env "$ENV_NAME" '
  .team_handoff.value | to_entries[] |
  "### Team `\(.key)`\n\nRepos allowed to deploy: \(.value.job_repos | map("`" + . + "`") | join(", "))\n\n| Variable | Value |\n|---|---|\n" +
  (.value.variables | to_entries | map("| `\(.key)` | `\(.value)` |") | join("\n")) +
  "\n\nWith the GitHub CLI:\n\n```bash\n" +
  ([.value.job_repos[] as $repo |
     "gh api --method PUT repos/\($repo)/environments/\($env) >/dev/null\n" +
     ((.value.variables | to_entries | map("gh variable set \(.key) --repo \($repo) --env \($env) --body \u0027\(.value)\u0027")) | join("\n"))
   ] | join("\n\n")) +
  "\n```\n"
' <<<"$teams"
