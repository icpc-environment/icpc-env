#!/bin/bash
# Print "<code> <vars>" for booting the VMs with secure boot: the distro's secure
# boot OVMF build, and a vars template with Microsoft's keys enrolled like on real
# hardware (so shim has to verify). The template is made once in tmp/ovmf/ with
# virt-fw-vars, since only some distros ship one with the keys already in.
set -euo pipefail

ROOT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )
VARS="$ROOT/tmp/ovmf/OVMF_VARS.ms.fd"

# code + blank vars, per distro: Arch, Debian/Ubuntu, Fedora
PAIRS=(
  "/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd"
  "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/OVMF/OVMF_VARS_4M.fd"
  "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd /usr/share/edk2/ovmf/OVMF_VARS.fd"
)

for pair in "${PAIRS[@]}"; do
  read -r code blank <<<"$pair"
  [ -f "$code" ] && [ -f "$blank" ] && break
  code=""
done
if [ -z "$code" ]; then
  echo "error: no secure boot OVMF firmware found, install your distro's ovmf/edk2-ovmf package" >&2
  exit 1
fi

if [ ! -f "$VARS" ]; then
  virt_fw_vars=virt-fw-vars
  [ -x "$ROOT/.venv/bin/virt-fw-vars" ] && virt_fw_vars="$ROOT/.venv/bin/virt-fw-vars"
  if ! hash "$virt_fw_vars" 2>/dev/null; then
    echo "error: virt-fw-vars not found, run 'just dependencies'" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$VARS")"
  if ! out=$("$virt_fw_vars" --input "$blank" --output "$VARS.tmp" --enroll-microsoft --secure-boot 2>&1); then
    echo "$out" >&2
    exit 1
  fi
  mv "$VARS.tmp" "$VARS"
fi

echo "$code $VARS"
