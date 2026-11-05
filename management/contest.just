# Day of contest commands, run as `just contest <recipe>` from the repo root.
# <fleet> is a fleet (bigsouth2026-southeast), a machine
# (icpc-team-100.bigsouth2026-southeast.icpcnet.internal), or all.
# See "Contest day" in management/README.md.

set positional-arguments
set shell := ['bash', '-cu']

# ansible's deprecation and group name warnings, on every command. Its other
# warnings stay, since they say when a fleet name matched nothing.
quiet := "grep -vE 'eprecation warnings|DEPRECATION WARNING|Invalid characters'"

[private]
default:
    @just --list contest

# Is the server itself OK: services, failed units, disk, memory, load
health:
    #!/usr/bin/env bash
    just mgmt ssh bash -s <<'EOF'
    for u in wg-fleet nginx coredns prometheus grafana-server icpc-backupd; do
      printf '%-16s %s\n' "$u" "$(systemctl is-active "$u")"
    done
    systemctl list-units --no-pager --plain --no-legend --state=failed
    systemctl list-units --no-pager --plain --no-legend 'wstunnel@*' | awk '{print $1, $4}'
    df -h /srv | tail -1
    free -h | sed -n 2p
    uptime
    EOF

# How many machines are connected per fleet, and what they are called
connected:
    #!/usr/bin/env bash
    just mgmt ssh bash -s <<'EOF'
    for f in $(jq -r '.fleets | if type == "array" then .[].name else keys[] end' /run/wg_fleets.json); do
      echo "$f: $(ansible "$f" --list-hosts 2>/dev/null | tail -n +2 | wc -l)"
    done
    echo
    ansible all --list-hosts 2>/dev/null | tail -n +2 | sed 's/^ *//' | sort
    EOF

# One line per connected machine: site, team, uptime, load, free disk, clock synced, who's logged in, last-minute revision
status fleet="all":
    #!/usr/bin/env bash
    just mgmt ssh bash -s -- "$1" <<'EOF' | {{quiet}} | sort
    ansible "$1" -b -o -m shell -a 'printf "site=%s team=[%s] up=%s load=%s free=%s ntp=%s user=%s rev=%s" "$(cat /icpc/SITE 2>/dev/null)" "$(cat /icpc/TEAM 2>/dev/null)" "$(uptime -p | sed "s/^up //; s/ //g")" "$(cut -d" " -f1 /proc/loadavg)" "$(df -h --output=avail / | tail -1 | tr -d " ")" "$(timedatectl show -p NTPSynchronized --value)" "$(who | cut -d" " -f1 | sort -u | paste -sd,)" "$(cut -c1-12 /icpc/update-version 2>/dev/null)"' \
      2>&1 | sed -E 's/ \| (CHANGED|SUCCESS) \| rc=0 \| \(stdout\)//'
    EOF

# uptime on every connected machine
uptime fleet="all":
    -@just mgmt ssh "ansible '$1' -o -m shell -a uptime" 2>&1 | {{quiet}} | sort

# Print jobs stuck in each machine's queue (machines with none print nothing)
printing fleet="all":
    -@just mgmt ssh "ansible '$1' -o -m shell -a 'lpstat -o'" 2>&1 | {{quiet}} | grep -v 'rc=0 | (stdout) *$' | sort

# Run a shell command as root on a fleet or machine, e.g. `just contest run bigsouth2026-southeast 'df -h /'`
run target +cmd:
    #!/usr/bin/env bash
    target=$1; shift
    printf -v remote 'ansible %q -b -m shell -a %q' "$target" "$*"
    just mgmt ssh "$remote" 2>&1 | {{quiet}}

# When each machine last backed up, including ones that are offline
backups fleet="":
    just mgmt backup-status "$1"

# The same, leaving out offline machines (old test machines stay listed forever)
backups-online fleet="":
    -@just mgmt backup-status "$1" | grep -v ' offline'

# Back up a fleet, or one machine, now
backup-now target:
    just mgmt backup-now "$1"

# Delete all of a fleet's backups, so repos start empty before the contest. Not after teams start work
[confirm("Delete every backup in this fleet?")]
purge-backups fleet:
    just mgmt ssh backup-admin purge "$1" --yes

# Grab every connected machine's screen, into https://<server>/contestweb/screens/
screenshots fleet="":
    just mgmt ssh do-screenshots $1

# Who registered, by real IP: time, source IP, fleet, site, hostname. `since` is for journalctl, e.g. "2 hours ago"
registered since="today":
    #!/usr/bin/env bash
    just mgmt ssh bash -s -- "'$1'" <<'EOF'
    journalctl -u wg-fleet --no-pager --since "$1" -o short-iso | python3 -c "$(cat <<'PY'
    import re, sys
    regs, hosts = [], {}
    for line in sys.stdin:
        m = re.search(r'Client registered: fleet=([^,]+), site=([^,]+), ip=([^,]+), source=(\S+)', line)
        if m:
            regs.append((line[:16], m[4], m[1], m[2], m[3]))
        m = re.search(r'Hostname updated: fleet=[^,]+, ip=([^,]+), hostname=(\S+)', line)
        if m:
            hosts[m[1]] = m[2]
    for time, source, fleet, site, ip in regs:
        print(time, source, fleet, site, hosts.get(ip, '?'), sep='\t')
    PY
    )"
    EOF

# Pull the last-minute repo on a fleet now, instead of at next boot. Changes machines
trigger-ansible fleet:
    just mgmt ssh "ansible '$1' -b -m file -a 'path=/icpc/trigger-ansible state=touch'" 2>&1 | {{quiet}}
