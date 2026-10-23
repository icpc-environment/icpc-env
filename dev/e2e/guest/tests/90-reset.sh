# Team reset, in two halves around the reboot it causes. `reset` leaves traces
# of a team behind, sets the next boot to the drive this booted from, and runs
# reset-team-account (which reboots). dev/e2e/run then waits for the machine
# and runs `reset_check`, which checks the traces are gone.

RESET_STATE=/var/tmp/icpc-e2e/reset-state

x_reset() {
  mkdir -p "$(dirname "$RESET_STATE")"
  : > "$RESET_STATE"
  # Traces a team leaves: files at home and on the desktop, shell history,
  # files outside home, the USB drive partition, a program in the exec audit log
  put $C/e2e-reset/solution.cpp <<< '// e2e-reset-marker solution'
  put $C/Desktop/e2e-reset-notes.txt <<< 'e2e-reset-marker notes'
  asc bash -c "echo 'echo e2e-reset-marker' >> $C/.bash_history"
  asc bash -c "echo e2e-reset-marker > /var/tmp/e2e-reset-marker"
  asc bash -c "echo e2e-reset-marker > /dev/shm/e2e-reset-marker"
  if [[ -w /mnt/usbdrive ]] || mountpoint -q /mnt/usbdrive; then
    asc bash -c "echo e2e-reset-marker > /mnt/usbdrive/e2e-reset-marker.txt" && echo usbdrive >> "$RESET_STATE"
  fi
  asc /bin/echo e2e-reset-audit-marker >/dev/null
  sleep 2
  if grep -rqs 'e2e-reset-audit-marker\|652D72657365742D61756469742D6D61726B6572' /var/log/audit/; then
    echo audit >> "$RESET_STATE"; pass "planted traces, including one in the exec audit log"
  else
    pass "planted traces (the audit log didn't show the marker, so that part isn't checked)"
  fi
  echo "uid $(id -u contestant)" >> "$RESET_STATE"
  echo "started $(date +%s)" >> "$RESET_STATE"

  # Boot back into this drive, not whatever the firmware's BootOrder prefers
  if [[ -d /sys/firmware/efi ]]; then
    local cur; cur=$(efibootmgr | sed -n 's/^BootCurrent: //p')
    echo "bootcurrent $cur" >> "$RESET_STATE"
    efibootmgr -n "$cur" >/dev/null && pass "set BootNext to $cur ($(efibootmgr | grep "^Boot$cur" | cut -c1-60))" || fail "efibootmgr -n $cur failed"
  else
    note "booted with BIOS; no BootNext to set"
  fi
  sync
  note "running reset-team-account; the machine reboots"
  sync
  /icpc/scripts/reset-team-account > "$OUT/reset-team-account.log" 2>&1
  sleep 120
  fail "still running two minutes after reset-team-account"
}
TIMEOUT[reset]=300

x_reset_check() {
  [[ -s $RESET_STATE ]] || { fail "no $RESET_STATE; run the reset test first"; return; }
  local started; started=$(awk '$1 == "started" {print $2}' "$RESET_STATE")
  local booted; booted=$(date -d "$(uptime -s)" +%s)
  (( booted > started )) && pass "the machine rebooted" || fail "no reboot since the reset started"
  local want; want=$(awk '$1 == "bootcurrent" {print $2}' "$RESET_STATE")
  if [[ -n $want ]]; then
    local cur; cur=$(efibootmgr | sed -n 's/^BootCurrent: //p')
    [[ $cur == "$want" ]] && pass "booted back into Boot$cur" || fail "booted Boot$cur, not Boot$want"
    efibootmgr | grep -q '^BootNext' && fail "BootNext is still set" || pass "BootNext was used up"
  fi
  [[ /icpc/team-reset-complete -nt $RESET_STATE ]] && pass "/icpc/team-reset-complete is new" || fail "/icpc/team-reset-complete is older than the reset"
  local f
  for f in $C/e2e-reset $C/Desktop/e2e-reset-notes.txt /var/tmp/e2e-reset-marker /dev/shm/e2e-reset-marker; do
    [[ -e $f ]] && fail "$f survived the reset" || pass "$f is gone"
  done
  grep -q e2e-reset-marker $C/.bash_history 2>/dev/null && fail "shell history survived" || pass "shell history is gone"
  if grep -qx usbdrive "$RESET_STATE"; then
    ls /mnt/usbdrive/e2e-reset-marker.txt >/dev/null 2>&1 && fail "the USB drive partition kept its files" || pass "the USB drive partition was wiped"
  fi
  if grep -qx audit "$RESET_STATE"; then
    grep -rqs 'e2e-reset-audit-marker\|652D72657365742D61756469742D6D61726B6572' /var/log/audit/ && fail "the exec audit log still has the old team's commands" || pass "the exec audit log was wiped"
  fi
  local left; left=$(find / -xdev -user contestant -newer /etc/hostname -not -path "$C/*" -not -path '/proc/*' -not -path '/run/*' -not -path '/tmp/*' -not -path '/var/tmp/icpc-e2e/*' 2>/dev/null | head -5)
  [[ -z $left ]] && pass "no contestant files outside home" || note "contestant files outside home: $left"
  [[ -d /var/lib/icpc-backup ]] && note "/var/lib/icpc-backup exists again (recreated since?)"
  # A fresh contestant is logged in again, with Firefox up
  wait_for 120 pgrep -u contestant -x xfce4-session && pass "the contestant desktop is back" || fail "no contestant desktop after the reset"
  wait_for 120 has_win 'Mozilla Firefox' && pass "Firefox autostarted" || fail "Firefox didn't autostart"
  settle 3 60; shot desktop
  ls -la $C > "$OUT/$CURRENT-home.txt"
}
