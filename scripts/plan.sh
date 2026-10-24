#!/usr/bin/env bash
set -euo pipefail
mode="${1:-apply}"
[[ "$mode" == apply || "$mode" == destroy ]] || { echo 'Expected apply or destroy' >&2; exit 1; }
root="$(git rev-parse --show-toplevel)"
cd "$root/live/dev/ec2"
set --
[[ "$mode" != destroy ]] || set -- -destroy
terragrunt init -input=false -lockfile=readonly
terragrunt plan -input=false -no-color -lock-timeout=5m "$@" -out=tfplan > "$root/plan.txt"
terragrunt show -json tfplan > "$root/plan.json"
python3 "$root/scripts/check_plan.py" "$root/plan.json" "$mode"
cat "$root/plan.txt"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '## Terraform plan'
    echo '```text'
    tail -c 40000 "$root/plan.txt"
    echo '```'
    echo 'Cost estimate: **~$6.77/month** for continuous operation (EC2 + 8 GiB gp3). No NAT or public IPv4.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
