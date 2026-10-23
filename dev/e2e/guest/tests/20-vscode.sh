# VS Code: open a file, set a breakpoint, debug it (F5), check it stops there
# and runs to completion. Kotlin has no debugger set up, so it's compiled and
# run in VS Code's terminal instead.

# Each program sums 1..4 and writes the result to a marker file after the
# breakpoint line, so the marker only appears once the debugger lets it go on
vscode_debug() {  # LANG FILE BREAKLINE PROCESS_REGEX PICKER_KEYS...  (source on stdin)
  local lang=$1 file=$2 line=$3 proc=$4; shift 4
  # A new folder each run: VS Code remembers breakpoints per folder, and F9 on
  # a remembered one would remove it
  local name=vscode-$lang-$(date +%s) marker=$WORK/vscode-$lang.out w
  local dir=$C/e2e/$name
  rm -f "$marker"
  put "$dir/$file"
  launch code-$lang code "$dir" "$dir/$file"
  w=$(wait_win 90 "^$file - $name - Visual Studio Code") || return
  maximize "$w"; settle 3 60
  # Extensions want a moment to activate before a debug session can start, and
  # F9 only places a breakpoint once a debugger for the language has registered
  sleep "${VSCODE_WARMUP:-5}"
  focus "$w"; key ctrl+g; sleep 0.7; typ "$line"; key Return; sleep 0.5
  key F9; sleep 0.5; key F5; sleep 3
  local k
  for k in "$@"; do
    focus "$w"
    case $k in
      type:*) typ "${k#type:}" ;;
      sleep:*) sleep "${k#sleep:}" ;;
      *) key "$k" ;;
    esac
    sleep 2
  done
  if wait_for 180 pgrep -u contestant -f "$proc"; then
    sleep 3
    shot paused
    if [[ -e $marker ]]; then fail "$lang: ran past the breakpoint"; else pass "$lang: stopped at the breakpoint on line $line"; fi
  else
    fail "$lang: the program never started under the debugger"; return
  fi
  # Continue from the command palette: after a stop the focus can be in the
  # debug terminal, which keeps F5 for itself
  focus "$w"; key ctrl+shift+p; sleep 1; typ "Debug: Continue"; sleep 1; key Return
  wait_marker 60 "$marker" 10 "$lang: ran to completion after continuing"
  shot done
}

t_vscode_c() {
  vscode_debug c hello.c 6 '/e2e/vscode-c-[0-9]+/hello$' Return <<EOF
#include <stdio.h>
int main(void) {
    int total = 0;
    for (int i = 1; i <= 4; i++)
        total += i;
    FILE *f = fopen("$WORK/vscode-c.out", "w");
    fprintf(f, "%d\\n", total);
    fclose(f);
    return 0;
}
EOF
}
TIMEOUT[vscode_c]=400

t_vscode_cpp() {
  # The picker lists gcc's configuration first; pick g++'s
  vscode_debug cpp hello.cpp 7 '/e2e/vscode-cpp-[0-9]+/hello$' 'type:g++ build' Return <<EOF
#include <bits/stdc++.h>
using namespace std;
int main() {
    vector<int> v{1, 2, 3, 4};
    int total = 0;
    for (int x : v) total += x;
    ofstream("$WORK/vscode-cpp.out") << total << endl;
    return 0;
}
EOF
}
TIMEOUT[vscode_cpp]=400

t_vscode_java() {
  # The Java extension starts its language server first, which takes a while
  vscode_debug java Hello.java 8 'java .*Hello$' <<EOF
import java.nio.file.*;

public class Hello {
    public static void main(String[] args) throws Exception {
        int total = 0;
        for (int i = 1; i <= 4; i++)
            total += i;
        Files.writeString(Path.of("$WORK/vscode-java.out"), total + "\\n");
    }
}
EOF
}
TIMEOUT[vscode_java]=500

t_vscode_python() {
  # Two pickers: which debugger (nothing preselected, so Down), then Python File
  VSCODE_WARMUP=20 vscode_debug python hello.py 4 'debugpy.*hello\.py' sleep:6 Down Return sleep:3 Return <<EOF
total = 0
for i in range(1, 5):
    total += i
print("total", total)
with open("$WORK/vscode-python.out", "w") as f:
    f.write(f"{total}\\n")
EOF
}
TIMEOUT[vscode_python]=400

t_vscode_kotlin() {
  local dir=$C/e2e/vscode-kotlin marker=$WORK/vscode-kotlin.out w
  rm -f "$marker"
  put "$dir/hello.kt" <<EOF
import java.io.File

fun main() {
    val total = (1..4).sum()
    File("$WORK/vscode-kotlin.out").writeText("\$total\\n")
}
EOF
  launch code-kotlin code "$dir" "$dir/hello.kt"
  w=$(wait_win 90 "^hello.kt - vscode-kotlin - Visual Studio Code") || return
  maximize "$w"; settle 3 60
  shot open
  focus "$w"; key ctrl+grave; sleep 3
  focus "$w"; typ 'kotlinc hello.kt -include-runtime -d hello.jar && java -jar hello.jar'; key Return
  wait_marker 180 "$marker" 10 "kotlin: compiled and ran in the VS Code terminal"
  shot done
}
TIMEOUT[vscode_kotlin]=300
