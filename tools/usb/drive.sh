# shellcheck shell=bash disable=SC2034
# Checks shared by write-usb and bench, sourced by both. Set DEVICE,
# MAX_GIB and ANY_TRANSPORT first; check_drive then sets TYPE, TRAN, SIZE
# and MODEL.

fail() {
  echo "FAILED: $*" >&2
  exit 1
}

# Partitions of /dev/sdb are /dev/sdb1, of /dev/loop0 and /dev/nvme0n1 are /dev/loop0p1 and /dev/nvme0n1p1
part() {
  if [[ $DEVICE =~ [0-9]$ ]]; then echo "${DEVICE}p$1"; else echo "${DEVICE}$1"; fi
}

# Anything mounted from the drive. A desktop automounts it under /media or
# /run/media, which is fine to undo; anywhere else means it's in use
mounts() {
  lsblk -lnpo NAME,MOUNTPOINT "$DEVICE" | awk 'NF == 2'
}

unmount_drive() {
  local dev target
  while read -r dev target; do
    echo "Unmounting $dev from $target"
    umount "$dev"
  done < <(mounts)
}

# Fails unless DEVICE is a whole usb drive that nothing on this machine is using
check_drive() {
  local dev target node pid
  TYPE=$(lsblk -dno TYPE "$DEVICE")
  TRAN=$(lsblk -dno TRAN "$DEVICE")
  SIZE=$(lsblk -dnbo SIZE "$DEVICE")
  MODEL=$(lsblk -dno MODEL "$DEVICE" | xargs)
  if [[ $ANY_TRANSPORT -eq 1 ]]; then
    [[ $TYPE == disk || $TYPE == loop ]] || fail "$DEVICE is a $TYPE, not a whole drive"
  else
    [[ $TYPE == disk ]] || fail "$DEVICE is a $TYPE, not a whole drive"
    [[ $TRAN == usb ]] || fail "$DEVICE is on ${TRAN:-an unknown bus}, not usb"
  fi

  # Following / down through any crypt, lvm or raid to the disks under it
  if lsblk -slnpo NAME,TYPE "$(findmnt -nvo SOURCE /)" | awk '$2 == "disk" { print $1 }' | grep -qxF "$DEVICE"; then
    fail "$DEVICE holds this machine's root filesystem"
  fi

  if lsblk -lnpo TYPE "$DEVICE" | tail -n +2 | grep -qv '^part$'; then
    fail "$DEVICE is in use by raid, lvm or crypt"
  fi

  while read -r dev target; do
    if [[ $target != /media/* && $target != /run/media/* ]]; then
      fail "$dev is mounted at $target, not touching a drive that's in use"
    fi
  done < <(mounts)

  # e.g. the station writing it. udev opens a drive briefly to probe it when
  # it's plugged in, so only what stays open counts
  for _ in $(seq 10); do
    pid=""
    for node in $(lsblk -lnpo NAME "$DEVICE"); do
      pid=$(find /proc/[0-9]*/fd -lname "$node" 2>/dev/null | head -1 | cut -d/ -f3)
      [[ -z "$pid" ]] || break
    done
    [[ -n "$pid" ]] || break
    sleep 0.5
  done
  if [[ -n "$pid" ]]; then
    fail "$node is open in $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-80)(pid $pid)"
  fi

  (( SIZE <= MAX_GIB * 1024 * 1024 * 1024 )) \
    || fail "$DEVICE is $((SIZE / 1000000000)) GB, bigger than --max-size $MAX_GIB GiB"
}
