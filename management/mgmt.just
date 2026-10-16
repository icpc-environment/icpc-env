# Management server, run as `just mgmt <recipe>` from the repo root.
# Recipes run from management/ so ansible picks up its ansible.cfg.
# See management/README.md.

set positional-arguments
set shell := ['bash', '-cu']

[private]
default:
    @just --list mgmt

# Provision the server (or apply changes). Extra args go to ansible-playbook, e.g. `just mgmt deploy --tags nginx`
deploy *args: preflight
    ansible-playbook site.yml --diff "$@"

# Show what deploy would change without changing it
check *args: preflight
    ansible-playbook site.yml --check --diff "$@"

# ssh to the server as root, or run a command there
ssh *args:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r host key < <(ansible-inventory --list | jq -r '._meta.hostvars | to_entries[0] | "\(.key) \(.value.ansible_ssh_private_key_file)"')
    exec ssh -i "${key/#\~/$HOME}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "root@$host" "$@"

# Follow a service's journal on the server (wg-fleet, nginx, coredns, grafana-server, prometheus, ...)
logs unit="wg-fleet":
    just mgmt ssh journalctl -fu "$1"

[private]
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f secret.yml ]; then
      echo "error: management/secret.yml is missing; copy secret.yml.example and fill it in" >&2
      exit 1
    fi
    id=$(sed -n 's/^mgmt_secrets_id: *//p' vars.yml)
    if [ ! -f "../secrets/$id/server_ca.pub" ]; then
      echo "error: secrets/$id is missing; run secrets/gen-secrets.sh $id" >&2
      exit 1
    fi
