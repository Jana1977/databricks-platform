#!/usr/bin/env bash
# Offline checks for every module, stack and bootstrap (no AWS or Databricks access):
#   - folders with tests/: `terraform test` (mocked providers; also validates the code)
#   - other folders:       `terraform validate`
#
#   scripts/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failed=()

for d in bootstrap modules/* stacks/*; do
  [[ -d "$d" ]] || continue
  echo "::group::$d"
  if ! terraform -chdir="$d" init -backend=false -input=false -no-color >/dev/null; then
    failed+=("$d (init)")
  elif [[ -d "$d/tests" ]]; then
    terraform -chdir="$d" test -no-color || failed+=("$d (test)")
  else
    terraform -chdir="$d" validate -no-color || failed+=("$d (validate)")
  fi
  echo "::endgroup::"
done

if ((${#failed[@]})); then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi
echo "All checks passed."
