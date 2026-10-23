#!/bin/bash
# Run e2e tests on this team machine (as root). Started by dev/e2e/run.
# Usage: runner.sh OUTDIR [TEST...]   (no tests: every test in the default set)
set -uo pipefail

OUT=$1; shift
mkdir -p "$OUT"
: > "$OUT/results.tsv"
cd /opt/icpc-e2e
source ./lib.sh
declare -A TIMEOUT   # per-test time limits in seconds, set by the test files
for f in tests/*.sh; do source "$f"; done

# Tests named t_* run by default; x_* (printing, team reset) only when asked for
mapfile -t ALL < <(declare -F | awk '{print $3}' | grep -E '^t_' | sed 's/^t_//')
mapfile -t EXPLICIT < <(declare -F | awk '{print $3}' | grep -E '^x_' | sed 's/^x_//')
if [[ $# -eq 0 ]]; then
  TESTS=("${ALL[@]}")
else
  TESTS=()
  for want in "$@"; do
    matched=0
    for t in "${ALL[@]}" "${EXPLICIT[@]}"; do
      # A trailing * selects every test with that prefix, e.g. vscode_*
      if [[ $t == $want ]]; then TESTS+=("$t"); matched=1; fi
    done
    (( matched )) || { echo "no test matches $want; tests: ${ALL[*]} ${EXPLICIT[*]}" >&2; exit 2; }
  done
fi

{
  echo "host	$(hostname)"
  echo "date	$(date -Is)"
  echo "version	$(cat /icpc/version 2>/dev/null)"
  echo "team	$(cat /icpc/TEAMNAME 2>/dev/null)"
  echo "root	$(lsblk -no MODEL "/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")" 2>/dev/null)"
} > "$OUT/info.tsv"

touch "$OUT/.start"
# Job control puts each test in its own process group, so a timeout can kill all of it
set -m
check_screen
for t in "${TESTS[@]}"; do
  CURRENT=$t
  log "=== $t"
  fn=t_$t; declare -F "$fn" >/dev/null || fn=x_$t
  start=$(date +%s)
  # Each test runs in a subshell with a time limit, so one hung app can't stall the rest
  ( set +e; "$fn" ) > "$OUT/$t.log" 2>&1 &
  pid=$!
  limit=${TIMEOUT[$t]:-${DEFAULT_TIMEOUT:-300}}
  while kill -0 $pid 2>/dev/null; do
    if (( $(date +%s) - start > limit )); then
      kill -TERM -- -$pid 2>/dev/null; kill $pid 2>/dev/null
      record FAIL "timed out after ${limit}s"
      shot timeout
      break
    fi
    sleep 1
  done
  wait $pid 2>/dev/null
  grep -q "^$t	" "$OUT/results.tsv" || record FAIL "test recorded no result"
  close_apps
  printf '%s\t%s\n' "$t" "$(( $(date +%s) - start ))" >> "$OUT/durations.tsv"
done
# Source files the tests left in the contestant's home, which the next backup should pick up
find $C -newer "$OUT/.start" -type f -size -1024k \( -name '*.c' -o -name '*.cpp' -o -name '*.java' -o -name '*.kt' -o -name '*.py' \) \
  -not -path '*/.*' -not -path '*/cmake-build-*' 2>/dev/null | sed 's|^/||' | sort > "$OUT/backup-expect.txt"
echo "done: $(grep -c '	ok	' "$OUT/results.tsv") ok, $(grep -c '	FAIL	' "$OUT/results.tsv") failed"
