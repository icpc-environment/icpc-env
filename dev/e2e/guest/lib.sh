# Helpers for the e2e tests, sourced by runner.sh. Everything runs as root on
# the team machine; apps are started as contestant in their desktop session.

C=/home/contestant
CUID=$(id -u contestant)
E2E=/opt/icpc-e2e
WORK=/tmp/e2e          # contestant-writable scratch: sources, marker files
mkdir -p "$WORK" && chown contestant: "$WORK"

# X clients the harness itself runs (xdotool, wmctrl, import) run as root, so
# they don't land in the contestant's exec audit log
X() { env DISPLAY=:0 XAUTHORITY=$C/.Xauthority "$@"; }

# Run a command as contestant with their desktop session's environment
asc() {
  local pid
  pid=$(pgrep -o -u contestant -x xfce4-session) || { echo "no contestant desktop session" >&2; return 1; }
  local -a env
  mapfile -t env < <(tr '\0' '\n' < /proc/$pid/environ |
    grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|HOME|PATH|LANG|USER|LOGNAME|SHELL|XDG_[A-Z_]+)=')
  setpriv --reuid="$CUID" --regid="$CUID" --init-groups env -i "${env[@]}" "$@"
}

# Start a GUI app as contestant under their systemd user manager (as the panel
# would), so it outlives the test's shell and isn't in its cgroup
launch() {  # NAME CMD...
  local name=$1; shift
  asc systemd-run --user --collect -q -p KillMode=process --unit "e2e-$name-$RANDOM" \
    -p StandardOutput=append:"$WORK/$name.log" -p StandardError=append:"$WORK/$name.log" -- "$@"
}

now() { date +%s.%N | cut -c1-14; }
log() { echo "[$(date +%T)] $*" >&2; }

# Results: one line per check, TEST<tab>STATUS<tab>DETAIL
record() { printf '%s\t%s\t%s\n' "$CURRENT" "$1" "$2" >> "$OUT/results.tsv"; log "$CURRENT: $1 $2"; }
pass() { record ok "$*"; }
fail() { record FAIL "$*"; shot "fail-$(date +%s%N | cut -c1-13)"; }
note() { record info "$*"; }
# check DESCRIPTION CMD...: pass if CMD succeeds
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }

shot() {  # NAME -> $OUT/$CURRENT-NAME.png
  X import -window root "$OUT/$CURRENT-$1.png" 2>/dev/null
}

settle() {  # QUIET TIMEOUT: wait for the screen to stop changing
  X python3 -I "$E2E/settle.py" "${1:-2}" "${2:-60}" >/dev/null
}

wait_for() {  # TIMEOUT CMD...: poll CMD every 0.25s until it succeeds
  local end=$(( $(date +%s) + $1 )); shift
  until "$@" >/dev/null 2>&1; do
    (( $(date +%s) < end )) || return 1
    sleep 0.25
  done
}

# Id of the newest top-level window whose title matches REGEX (and WM_CLASS
# matches CLASS, if given). wmctrl only lists managed windows, minimized ones too
win() {  # REGEX [CLASS]
  X wmctrl -lx | RE=$1 CLS=${2:-} awk '{
      id = $1; c = $3; $1 = $2 = $3 = $4 = ""; t = substr($0, 5)
      if (t ~ ENVIRON["RE"] && (ENVIRON["CLS"] == "" || c ~ ENVIRON["CLS"])) last = id
    } END { if (last) print last }'
}
has_win() { [[ -n $(win "$@") ]]; }
no_win() { [[ -z $(win "$@") ]]; }

# Raise, un-minimize and focus a window. Apps (Firefox especially) take the
# focus back now and then, so do this before every burst of keys
focus() { X wmctrl -ia "$1"; X xdotool windowactivate --sync "$(( $1 ))" 2>/dev/null; sleep 0.3; }

# Wait for a window, focus it (xfwm's focus stealing prevention can leave a
# new window behind the one that opened it) and print its id
wait_win() {  # TIMEOUT REGEX [CLASS]
  local t=$1; shift
  wait_for "$t" has_win "$@" || { fail "no window matching '$1' within ${t}s"; return 1; }
  local w; w=$(win "$@")
  focus "$w"
  echo "$w"
}

maximize() { X wmctrl -ir "$1" -b add,maximized_vert,maximized_horz; sleep 0.5; }
# Close a window the way its close button would
close_win() { X wmctrl -ic "$1"; }
key() { X python3 -I "$E2E/keys.py" "$@"; }
typ() { X xdotool type --delay 40 -- "$1"; }
click() { X xdotool mousemove "$1" "$2" click "${3:-1}"; }
# Click relative to a window's top left corner
wclick() {  # WIN DX DY
  [[ -n $1 ]] || { echo "wclick: no window" >&2; return 1; }
  local X Y WIDTH HEIGHT SCREEN WINDOW
  eval "$(X xdotool getwindowgeometry --shell "$(( $1 ))")"
  click $((X + $2)) $((Y + $3))
}

# Write a file as contestant
put() {  # PATH (content on stdin)
  asc mkdir -p "$(dirname "$1")"
  asc tee "$1" >/dev/null
}

# Pass when a marker file a test program writes appears with the expected content
wait_marker() {  # TIMEOUT PATH EXPECTED DESCRIPTION
  if wait_for "$1" grep -qx "$3" "$2"; then pass "$4"; else fail "$4 (no '$3' in $2 after $1s)"; fi
}

# Close every app the tests may have opened, leaving the session (and Firefox,
# which autostarts) alone unless asked
APPS='/opt/intellij-idea|/opt/clion|/opt/pycharm|/opt/eclipse|/usr/share/code/|[g]vim|nvim|emacs|kate|gedit|mousepad|geany|codelite|mate-calc|mupdf|xfce4-terminal'
close_apps() {
  pkill -u contestant -f "$APPS"; sleep 2
  pkill -9 -u contestant -f "$APPS"; sleep 1
}

# IDE settings as the image ships them, snapshotted on the suite's first run
# so each IDE test starts like a fresh team's first launch
IDE_STATE=(.config/JetBrains .java .eclipse .p2)
IDE_SNAPSHOT=/var/tmp/icpc-e2e/ide-pristine.tgz
ide_snapshot() {
  [[ -s $IDE_SNAPSHOT ]] && return
  mkdir -p "$(dirname "$IDE_SNAPSHOT")"
  local have=() p
  for p in "${IDE_STATE[@]}"; do [[ -e $C/$p ]] && have+=("contestant/$p"); done
  tar -C /home -czf "$IDE_SNAPSHOT" "${have[@]}" 2>/dev/null || tar -C /home -czf "$IDE_SNAPSHOT" --files-from /dev/null
}
ide_reset() {
  ide_snapshot
  local p
  for p in "${IDE_STATE[@]}" .cache/JetBrains .local/share/JetBrains IdeaProjects CLionProjects PycharmProjects eclipse-workspace; do
    rm -rf "${C:?}/$p"
  done
  tar -C /home -xzf "$IDE_SNAPSHOT"
}

# Like wclick, but on the newest window of CLASS whose size is WxH (dialogs
# whose title is empty or changes from page to page)
win_sized() {  # CLASS W H
  X wmctrl -lGx | awk -v c="$1" -v w="$2" -v h="$3" '$7 ~ c && $5 == w && $6 == h { id = $1 } END { if (id) print id }'
}

# The clicks in the IDE tests are laid out for a 1680x1050 screen
check_screen() {
  local size; size=$(X xdpyinfo | awk '/dimensions:/ {print $2}')
  [[ $size == 1680x1050 ]] || log "warning: screen is $size; the IDE tests click where things are at 1680x1050"
}
