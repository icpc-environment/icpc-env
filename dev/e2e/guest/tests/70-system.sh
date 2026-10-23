# System health: the image's own self test, services, firewall, backups

t_self_test() {
  local out rc
  out=$(/icpc/scripts/self_test 2>&1); rc=$?
  printf '%s\n' "$out" > "$OUT/$CURRENT-output.txt"
  (( rc == 0 )) && pass "self_test exited 0" || fail "self_test exited $rc"
  local bad
  # self_test prints each check as "description ... Pass/Fail", or a URL under a heading
  bad=$(grep -E '(^|\s)Fail\s*$' <<<"$out" | sed 's/  */ /g' | head -5)
  [[ -z $bad ]] && pass "self_test reported nothing failing" || fail "self_test: $(tr '\n' ';' <<<"$bad")"
}

t_services() {
  local failed u
  failed=$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
  [[ -z $failed ]] && pass "no failed systemd units" || fail "failed units: $failed"
  for u in squid nginx devdocs cups icpc-printer; do
    systemctl is-active -q "$u" && pass "$u is running" || fail "$u is not running"
  done
  /icpc/scripts/firewall status && pass "firewall enabled" || fail "firewall status says it's off"
  local root_use; root_use=$(df --output=pcent / | tail -1 | tr -dc 0-9)
  (( root_use < 90 )) && pass "root filesystem ${root_use}% full" || fail "root filesystem ${root_use}% full"
  # Contestant has no sudo and no way to the admin account
  if asc sudo -n true 2>/dev/null; then fail "contestant can sudo"; else pass "contestant can't sudo"; fi
  local lines
  lines=$(journalctl -b -p err --no-pager -q | grep -vE 'e2e|kernel: (ACPI|tpm)' | wc -l)
  note "$lines error-level journal lines this boot (see $CURRENT-journal.txt)"
  journalctl -b -p err --no-pager -q > "$OUT/$CURRENT-journal.txt"
}

t_backup_client() {
  local cfg; cfg=$(jq -r '.backup.enabled // empty' /icpc/config.json)
  [[ $cfg == true ]] || { note "backups are off in /icpc/config.json"; return; }
  if [[ -s /run/icpc-backup/status.json ]]; then
    local last age
    last=$(jq -r '.last_success // empty' /run/icpc-backup/status.json)
    if [[ -n $last ]]; then
      age=$(( $(date +%s) - $(date -d "$last" +%s 2>/dev/null || echo "$last") ))
      (( age < 1800 )) && pass "last backup ${age}s ago" || fail "last backup ${age}s ago"
    else
      fail "no successful backup yet: $(head -c 300 /run/icpc-backup/status.json)"
    fi
  else
    note "no backup has run since boot or the last team reset"
  fi
}

# The last-minute ansible-pull: trigger it the way the docs say and check it
# pulls and applies the fleet's repo
t_ansible_pull() {
  local url; url=$(sed -n 's/^ANSIBLE_PULL_URL="\?\([^"]*\)"\?/\1/p' /icpc/CONFIG)
  [[ -n $url ]] || { note "no ANSIBLE_PULL_URL in /icpc/CONFIG (no management server)"; return; }
  note "pull URL: $url"
  systemctl is-enabled -q ansible-pull.path && pass "ansible-pull.path is enabled" || fail "ansible-pull.path isn't enabled"
  local since; since=$(date '+%F %T')
  touch /icpc/trigger-ansible
  wait_for 20 bash -c '[[ $(systemctl show -p ActiveState --value ansible-pull.service) == activating ]]' \
    && pass "creating /icpc/trigger-ansible started ansible-pull" || { fail "ansible-pull didn't start"; return; }
  wait_for 240 bash -c '[[ $(systemctl show -p ActiveState --value ansible-pull.service) != activating ]]'
  journalctl -u ansible-pull --since "$since" --no-pager > "$OUT/$CURRENT-journal.txt"
  [[ $(systemctl show -p Result --value ansible-pull.service) == success ]] && pass "ansible-pull succeeded" || fail "ansible-pull: $(systemctl show -p Result --value ansible-pull.service)"
  grep -q 'failed=0' "$OUT/$CURRENT-journal.txt" && pass "playbook ran with no failed tasks" || fail "see $CURRENT-journal.txt"
  [[ ! -e /icpc/trigger-ansible ]] && pass "the playbook removed the trigger file" || fail "/icpc/trigger-ansible is still there"
  note "applied revision $(git -C /root/ansible-pull rev-parse --short HEAD) from $(git -C /root/ansible-pull remote get-url origin)"
}
TIMEOUT[ansible_pull]=360
