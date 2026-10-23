# JetBrains IDEs: create a project with the New Project wizard as a first-time
# user would, put a program in it that writes a marker file, and run it.
# Clicks are relative to the dialogs, whose layout is fixed at 1680x1050.

# The project frame: the IDE's only window wider than its dialogs
jb_frame() { X wmctrl -lGx | awk -v c="$1" '$7 ~ c && $5 > 1000 { id = $1 } END { if (id) print id }'; }
has_jb_frame() { [[ -n $(jb_frame "$1") ]]; }

# "Meet the Islands Theme" pops up over a new project once, and the project's
# main file only opens after it's dismissed. Wait for the editor window
# (title "PROJECT – FILE"), skipping the popup whenever it shows up, and print
# the editor window's title
jb_wait_editor() {  # CLASS FILE_REGEX TIMEOUT
  local end=$(( $(date +%s) + $3 )) p t
  while (( $(date +%s) < end )); do
    p=$(X wmctrl -lGx | awk -v c="$1" '$7 ~ c && $5 < 600 && $6 > 300 { id = $1 } END { if (id) print id }')
    if [[ -n $p ]]; then
      sleep 1; wclick "$p" 191 440; note "dismissed the Meet the Islands Theme popup"; sleep 2
    fi
    t=$(X wmctrl -lx | awk -v c="$1" '$3 ~ c { $1 = $2 = $3 = $4 = ""; print substr($0, 5) }' | grep -E " .+ $2\$" | tail -1)
    [[ -n $t ]] && { echo "$t"; return 0; }
    sleep 1
  done
  fail "no editor for $2 within $3s"; return 1
}

# From the welcome screen, click New Project
jb_new_project_dialog() {  # WELCOME_TITLE
  local w
  w=$(wait_win 240 "^$1\$") || return 1
  settle 3 120
  shot welcome
  wclick "$w" 381 248
  wait_win 60 '^New Project$' >/dev/null || return 1
  settle 2 60
}

# Rewrite SOURCE with a program writing MARKER and run the current file with
# Ctrl+Shift+F10, waiting up to TIMEOUT for the marker. The IDE may notice the
# file changed under an open editor and ask which version to keep; take the
# disk's and run again.
jb_run() {  # FRAME SOURCE MARKER TIMEOUT (program on stdin)
  local f=$1 end=$(( $(date +%s) + $4 ))
  rm -f "$3"
  maximize "$f"; focus "$f"; key ctrl+s; sleep 1
  put "$2"
  focus "$f"; key ctrl+alt+y; sleep 2
  click 1000 600; sleep 1
  key ctrl+shift+F10
  while (( $(date +%s) < end )); do
    [[ -s $3 ]] && return 0
    # CLion's trial licence key brings up "Evaluation Feedback" now and then
    if has_win '^Evaluation Feedback$'; then
      shot evaluation-feedback
      note "the IDE interrupted with an Evaluation Feedback dialog (trial licence); closed it"
      focus "$(win '^Evaluation Feedback$')"; key Escape; sleep 2
      focus "$f"; click 1000 600; sleep 1; key ctrl+shift+F10
    fi
    # CLion's CMake profile setup, with detected defaults: OK
    if has_win '^Open Project Wizard$'; then
      shot open-project-wizard
      note "CLion showed its Open Project Wizard (CMake profile); accepted the defaults"
      focus "$(win '^Open Project Wizard$')"; key Escape; sleep 0.5; key Return; sleep 3
      focus "$f"; click 1000 600; sleep 1; key ctrl+shift+F10
    fi
    if has_win '^File Cache Conflict$'; then
      note "the IDE asked whether to keep its copy of the file; loaded the disk's"
      focus "$(win '^File Cache Conflict$')"; key Return; sleep 2
      focus "$f"; click 1000 600; sleep 1; key ctrl+shift+F10
    fi
    sleep 1
  done
  return 1
}

jb_project() {  # LANG(java|kotlin)
  local lang=$1 name=e2e-$1 src
  ide_reset
  launch idea intellij-idea
  jb_new_project_dialog 'Welcome to IntelliJ IDEA' || return
  local d; d=$(win '^New Project$')
  [[ $lang == kotlin ]] && { wclick "$d" 50 72; sleep 1; }
  shot wizard
  wclick "$d" 490 9; key ctrl+a; typ "$name"; key Return
  wait_for 240 has_jb_frame jetbrains-idea || { fail "no project window"; return; }
  if [[ $lang == java ]]; then src=Main.java; else src=Main.kt; fi
  local title; title=$(jb_wait_editor jetbrains-idea "$src" 240) || return
  # The name typed into the wizard can be lost if the dialog was still busy
  local got=${title%% *}
  [[ $got == "$name" ]] || note "the project was created as '$got', not '$name'"
  name=$got
  pass "created a $lang project; $src opened"
  shot project
  local marker=$WORK/intellij-$lang.out
  if [[ $lang == java ]]; then
    jb_run "$(jb_frame jetbrains-idea)" "$C/IdeaProjects/$name/src/Main.java" "$marker" 300 <<EOF
void main() {
    int total = 0;
    for (int i = 1; i <= 4; i++) total += i;
    IO.println("total " + total);
    try { java.nio.file.Files.writeString(java.nio.file.Path.of("$marker"), total + "\\n"); }
    catch (java.io.IOException e) { throw new RuntimeException(e); }
}
EOF
  else
    jb_run "$(jb_frame jetbrains-idea)" "$C/IdeaProjects/$name/src/Main.kt" "$marker" 300 <<EOF
import java.io.File

fun main() {
    val total = (1..4).sum()
    println("total \$total")
    File("$marker").writeText("\$total\\n")
}
EOF
  fi
  wait_marker 5 "$marker" 10 "$lang: built and ran with Ctrl+Shift+F10"
  settle 2 30; shot ran
}

t_intellij_java() { jb_project java; }
TIMEOUT[intellij_java]=900
t_intellij_kotlin() { jb_project kotlin; }
TIMEOUT[intellij_kotlin]=900

t_clion() {
  ide_reset
  launch clion clion
  jb_new_project_dialog 'Welcome to CLion' || return
  shot wizard
  # C++ Executable is preselected; Create
  wclick "$(win '^New Project$')" 657 567
  wait_for 240 has_jb_frame jetbrains-clion || { fail "no project window"; return; }
  jb_wait_editor jetbrains-clion main.cpp 300 >/dev/null || return
  pass "created a C++ executable project; main.cpp opened"
  # CMake has to finish configuring before there's anything to run
  wait_for 240 test -d $C/CLionProjects/untitled/cmake-build-debug/CMakeFiles || { fail "CMake never configured the project"; return; }
  settle 3 120
  shot project
  local marker=$WORK/clion.out
  jb_run "$(jb_frame jetbrains-clion)" "$C/CLionProjects/untitled/main.cpp" "$marker" 300 <<EOF
#include <fstream>
#include <iostream>
int main() {
    int total = 0;
    for (int i = 1; i <= 4; i++) total += i;
    std::cout << "total " << total << std::endl;
    std::ofstream("$marker") << total << std::endl;
    return 0;
}
EOF
  wait_marker 5 "$marker" 10 "built with CMake and ran"
  settle 2 30; shot ran
}
TIMEOUT[clion]=900

t_pycharm() {
  ide_reset
  launch pycharm pycharm
  # On a machine where other JetBrains IDEs have settings, PyCharm first offers to import them
  local w
  if wait_for 180 has_win '^(PyCharm|WelcomeScreen.*)$' jetbrains-pycharm; then
    w=$(win '^PyCharm$' jetbrains-pycharm)
    if [[ -n $w ]]; then
      settle 2 60; shot import; wclick "$w" 315 255; note "skipped PyCharm's Import Settings screen"
    fi
  fi
  w=$(wait_win 180 '^WelcomeScreen' jetbrains-pycharm) || return
  settle 3 120; shot welcome
  # Main menu (the hamburger) > File > New Project...
  focus "$w"; click 200 66; sleep 1.5; click 262 105
  local d; d=$(wait_win 60 '^New Project$') || return
  settle 2 60; shot wizard
  wclick "$d" 950 669
  wait_win 240 'PythonProject . main.py' >/dev/null || return
  pass "created a Pure Python project with a venv; main.py opened"
  [[ -x $C/PycharmProjects/PythonProject/.venv/bin/python ]] && pass "project venv created" || fail "no .venv/bin/python"
  settle 3 120; shot project
  local marker=$WORK/pycharm.out
  jb_run "$(jb_frame jetbrains-pycharm)" "$C/PycharmProjects/PythonProject/main.py" "$marker" 180 <<EOF
total = sum(range(1, 5))
print("total", total)
with open("$marker", "w") as f:
    f.write(f"{total}\\n")
EOF
  wait_marker 5 "$marker" 10 "ran main.py with Ctrl+Shift+F10"
  settle 2 30; shot ran
}
TIMEOUT[pycharm]=900
