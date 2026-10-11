#!/bin/bash
# Print the path of the icpcadmin ssh key for a variant's contest_id (default: the `all` group)
set -euo pipefail

VARIANT=${1:-all}
ROOT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )

ansible_inventory=ansible-inventory
[ -x "$ROOT/.venv/bin/ansible-inventory" ] && ansible_inventory="$ROOT/.venv/bin/ansible-inventory"

INVENTORY_FILE=$(mktemp)
trap 'rm -f "$INVENTORY_FILE"' EXIT
printf 'vm\n[%s]\nvm\n' "$VARIANT" > "$INVENTORY_FILE"

contest_id=$("$ansible_inventory" -i "$INVENTORY_FILE" --playbook-dir "$ROOT" --host vm </dev/null |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["contest_id"])')
echo "$ROOT/secrets/$contest_id/icpcadmin@contestmanager"
