#!/bin/bash
# Launch each contestant tool on the VM's desktop, screenshot it and close it,
# then compile/run a hello world per language. Run via `just vm smoke [tool...]`.
set -uo pipefail

OUT="$VM_STATE/smoke/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
RESULTS="$OUT/results.txt"

gui() { just vm gui "$@"; }
record() { printf '%-14s %-4s %s\n' "$1" "$2" "$3" | tee -a "$RESULTS"; }

# name | command | process to kill if it won't close | seconds to let it draw
TOOLS=(
  "vscode|code /tmp/smoke/hello.cpp|/usr/share/code/code|12"
  "gvim|gvim /tmp/smoke/hello.cpp|gvim|3"
  "neovim-qt|nvim-qt /tmp/smoke/hello.cpp|nvim|4"
  "emacs|emacs /tmp/smoke/hello.cpp|emacs|5"
  "kate|kate /tmp/smoke/hello.cpp|kate|5"
  "gedit|gedit /tmp/smoke/hello.cpp|gedit|4"
  "mousepad|mousepad /tmp/smoke/hello.cpp|mousepad|3"
  "xfce4-terminal|xfce4-terminal|xfce4-terminal|3"
  "konsole|konsole|konsole|4"
  "alacritty|alacritty|alacritty|3"
  "kitty|kitty|kitty|3"
  "ghostty|ghostty|ghostty|5"
  "firefox|firefox|firefox|10"
)

SOURCES='
mkdir -p /tmp/smoke && cd /tmp/smoke
printf "#include <stdio.h>\nint main(void) { puts(\"hello c\"); return 0; }\n" > hello.c
printf "#include <iostream>\nint main() { std::cout << \"hello cpp\" << std::endl; }\n" > hello.cpp
printf "public class Hello { public static void main(String[] a) { System.out.println(\"hello java\"); } }\n" > Hello.java
printf "fun main() { println(\"hello kotlin\") }\n" > hello.kt
printf "print(\"hello python\")\n" > hello.py
'

window_ids() { gui 'wmctrl -l | cut -d" " -f1' | sort; }

smoke_tool() {
  local name=$1 cmd=$2 proc=$3 settle=$4
  local before after new deadline
  before=$(window_ids)
  gui "setsid -f $cmd >/tmp/smoke/$name.log 2>&1 </dev/null"
  deadline=$((SECONDS + 60))
  new=""
  while [ -z "$new" ] && (( SECONDS < deadline )); do
    sleep 1
    after=$(window_ids)
    new=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
  done
  if [ -z "$new" ]; then
    just vm screenshot "$OUT/$name.png" >/dev/null
    record "$name" FAIL "no window within 60s, see /tmp/smoke/$name.log in the guest"
  else
    gui "wmctrl -ir $new -b add,maximized_vert,maximized_horz; wmctrl -ia $new"
    sleep "$settle"
    just vm screenshot "$OUT/$name.png" >/dev/null
    record "$name" ok "$(gui "wmctrl -lx | grep ^$new" | awk '{print $3}')"
    gui "wmctrl -ic $new"
    sleep 2
  fi
  # Bracket the first character so the pattern doesn't match the shell running pkill
  gui "pkill -f '[${proc:0:1}]${proc:1}' || true"
  sleep 1
}

language() {
  local name=$1 cmd=$2 want=$3 got
  got=$(gui "cd /tmp/smoke && $cmd" 2>&1 | tail -1)
  if [ "$got" = "$want" ]; then record "$name" ok "$want"; else record "$name" FAIL "$got"; fi
}

tool_version() {
  local name=$1 cmd=$2 got
  if got=$(gui "$cmd" 2>&1 | head -1); then record "$name" ok "$got"; else record "$name" FAIL "$got"; fi
}

just vm wait-desktop 120 >/dev/null || { echo "error: no desktop session" >&2; exit 1; }
gui "$SOURCES"
echo "Results and screenshots in $OUT"

for t in "${TOOLS[@]}"; do
  IFS='|' read -r name cmd proc settle <<<"$t"
  if [ $# -eq 0 ] || [[ " $* " == *" $name "* ]]; then
    smoke_tool "$name" "$cmd" "$proc" "$settle"
  fi
done

if [ $# -eq 0 ] || [[ " $* " == *" languages "* ]]; then
  language c "gcc -O2 -o hello_c hello.c && ./hello_c" "hello c"
  language cpp "g++ -O2 -o hello_cpp hello.cpp && ./hello_cpp" "hello cpp"
  language java "javac Hello.java && java Hello" "hello java"
  language kotlin "kotlinc hello.kt -include-runtime -d hello.jar 2>/dev/null && java -jar hello.jar" "hello kotlin"
  language python3 "python3 hello.py" "hello python"
  language pypy3 "pypy3 hello.py" "hello python"
  tool_version gdb "gdb --version"
  tool_version valgrind "valgrind --version"
  tool_version zsh "zsh --version"
fi

echo
echo "$(grep -c ' ok ' "$RESULTS") ok, $(grep -c ' FAIL ' "$RESULTS") failed"
! grep -q ' FAIL ' "$RESULTS"
