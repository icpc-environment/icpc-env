#!/bin/bash
# Provision an image by chrooting into it instead of booting it under qemu.
#
# Much faster to iterate on than build-final.sh, but the chroot has no running
# init, so anything needing a live system is skipped - see the
# `ansible_connection != "chroot"` guards in the playbooks. Use build-final.sh
# to produce an image for distribution.
set -euo pipefail

VARIANT=${1:-generic}
BASEIMG="${BASEIMG:-base-amd64.img}"
IMGFILE="${IMGFILE:-output/$VARIANT-$(date +%Y-%m-%d)_image-amd64.img}"
MNT="$PWD/tmp/chroot"

if [ "$EUID" -ne 0 ]; then
  echo "losetup/mount need root - re-run with sudo" >&2
  exit 1
fi

LOOPDEV=""
cleanup() {
  set +e
  # -R so the proc/sys/dev mounts under it come apart too, in the right order
  mountpoint -q "$MNT" && umount -R "$MNT"
  [ -n "$LOOPDEV" ] && losetup --detach "$LOOPDEV"
}
trap cleanup EXIT

if [ ! -f "$IMGFILE" ]; then
  echo "Creating $IMGFILE from output/$BASEIMG"
  qemu-img convert -O raw "output/$BASEIMG" "$IMGFILE"
fi

mkdir -p "$MNT"
LOOPDEV=$(losetup --show --partscan -f "$IMGFILE")

# Partition numbering comes from configs/*_autoinstall.yaml: p2 is EFI, p4 is root
mount "${LOOPDEV}p4" "$MNT"
mount "${LOOPDEV}p2" "$MNT/boot/efi"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
mount --bind /dev "$MNT/dev"
mount -t devpts pts "$MNT/dev/pts"

INVENTORY_FILE=$(mktemp)
cat <<EOF > "$INVENTORY_FILE"
vm ansible_connection=chroot ansible_host=$MNT
[$VARIANT]
vm
EOF

ansible-playbook -i "$INVENTORY_FILE" --diff --become main.yml
rm -f "$INVENTORY_FILE"

echo "Provisioned $IMGFILE"
