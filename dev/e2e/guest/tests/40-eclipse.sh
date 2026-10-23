# Eclipse: Java, PyDev and CDT projects from the New wizard (Ctrl+N), each
# with a program that writes a marker file, run from the Run menu (Ctrl+F11
# is xfwm's "workspace 11" key, so it never reaches Eclipse).

eclipse_start() {
  ide_reset
  launch eclipse /opt/eclipse/eclipse
  local l; l=$(wait_win 180 '^Eclipse IDE Launcher$') || return 1
  settle 2 60; shot launcher
  focus "$l"; key Return
  local w; w=$(wait_win 300 'Eclipse IDE$') || return 1
  settle 5 240
  maximize "$w"; settle 2 30
  shot workbench
}

# Ctrl+N, filter the wizard list, click the entry at row ROW (0-based, under
# its category; - keeps the filter's own selection) and press Next
eclipse_wizard() {  # FILTER ROW
  focus "$(win 'Eclipse IDE$')"; key ctrl+n
  local d; d=$(wait_win 30 '^New$') || return 1
  sleep 1; typ "$1"; sleep 1.5
  [[ $2 == - ]] || { wclick "$d" 108 $(( 143 + 23 * $2 )); sleep 0.5; }
  shot "wizard-$1"
  wclick "$d" 302 409; sleep 3
}

# Refresh every project (files were written behind Eclipse's back), open FILE
# with Open Resource and run it from the Run menu
eclipse_refresh_all() {
  local w; w=$(win 'Eclipse IDE$')
  maximize "$w"; focus "$w"; click 60 150; sleep 0.3; key ctrl+a; key F5; sleep 3
}
# Open Resource leaves the focus in FILE's editor, so Run runs FILE
eclipse_open() {  # FILE
  key ctrl+shift+r; sleep 2; typ "$1"; sleep 2; key Return; sleep 3
}
eclipse_run() {  # FILE
  eclipse_refresh_all
  eclipse_open "$1"
  key alt+r; sleep 1; key Return; sleep 3
  # The first run of a file asks how to run it; the first choice is right
  if has_win '^Run As$'; then shot run-as; focus "$(win '^Run As$')"; key Return; fi
}

t_eclipse_java() {
  eclipse_start || return
  eclipse_wizard 'Java Project' - || return
  typ ejava; sleep 0.5; key Return
  wait_for 60 test -f $C/eclipse-workspace/ejava/.project && pass "created a Java project" || { fail "no Java project"; return; }
  settle 3 60
  local marker=$WORK/eclipse-java.out; rm -f "$marker"
  # The wizard makes a module-info.java, so the class goes in a package
  put $C/eclipse-workspace/ejava/src/e2e/Hello.java <<EOF
package e2e;

public class Hello {
    public static void main(String[] args) throws Exception {
        int total = 0;
        for (int i = 1; i <= 4; i++) total += i;
        System.out.println("total " + total);
        java.nio.file.Files.writeString(java.nio.file.Path.of("$marker"), total + "\\n");
    }
}
EOF
  eclipse_run Hello.java
  wait_marker 120 "$marker" 10 "built and ran Hello.java"
  settle 2 30; shot ran
}
TIMEOUT[eclipse_java]=600

t_eclipse_pydev() {
  eclipse_start || return
  eclipse_wizard 'PyDev' 5 || return
  typ epy; sleep 0.5
  local d; d=$(win_sized Eclipse 607 829)
  shot interpreter
  # No interpreter is configured out of the box: "Please configure an
  # interpreter", then "Config first in PATH"
  wclick "$d" 172 397
  local c; c=$(wait_win 30 '^Configure interpreter$') || return
  note "PyDev has no interpreter configured; used Config first in PATH"
  wclick "$c" 194 54; sleep 8
  shot configured
  wclick "$(win_sized Eclipse 607 829)" 535 767
  if wait_for 30 has_win 'Open Associated Perspective'; then focus "$(win 'Open Associated Perspective')"; key Return; fi
  wait_for 60 test -f $C/eclipse-workspace/epy/.project && pass "created a PyDev project" || { fail "no PyDev project"; return; }
  settle 3 60
  local marker=$WORK/eclipse-pydev.out; rm -f "$marker"
  put $C/eclipse-workspace/epy/hello.py <<EOF
total = sum(range(1, 5))
print("total", total)
with open("$marker", "w") as f:
    f.write(f"{total}\\n")
EOF
  eclipse_refresh_all
  eclipse_open hello.py
  # Opening the first Python file asks to change some Eclipse defaults
  if wait_for 15 has_win 'Default Eclipse preferences for PyDev'; then
    shot pydev-prefs; focus "$(win 'Default Eclipse preferences for PyDev')"; key Return; sleep 2
    focus "$(win 'Eclipse IDE$')"; eclipse_open hello.py
  fi
  key alt+r; sleep 1; key Return; sleep 3
  if has_win '^Run As$'; then focus "$(win '^Run As$')"; key Return; fi
  wait_marker 120 "$marker" 10 "ran hello.py"
  settle 2 30; shot ran
}
TIMEOUT[eclipse_pydev]=600

t_eclipse_cdt() {
  eclipse_start || return
  eclipse_wizard 'C/C' - || return
  local d; d=$(win '^New C/C.. Project$')
  # Classic C++ Project, Next
  wclick "$d" 263 119; sleep 0.5; wclick "$d" 302 409; sleep 3
  typ ecpp
  d=$(win_sized Eclipse 607 585)
  # Executable > Hello World C++ Project, Linux GCC; Finish
  wclick "$d" 146 252; sleep 0.5
  shot hello-world
  wclick "$d" 535 523
  wait_for 60 test -f $C/eclipse-workspace/ecpp/src/ecpp.cpp && pass "created a Hello World C++ project" || { fail "no CDT project"; return; }
  settle 3 60
  local marker=$WORK/eclipse-cdt.out; rm -f "$marker"
  put $C/eclipse-workspace/ecpp/src/ecpp.cpp <<EOF
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
  eclipse_refresh_all
  eclipse_open ecpp.cpp
  key ctrl+b
  wait_for 120 test -x $C/eclipse-workspace/ecpp/Debug/ecpp && pass "built with Ctrl+B" || fail "no Debug/ecpp after Ctrl+B"
  key alt+r; sleep 1; key Return; sleep 3
  if has_win '^Run As$'; then shot run-as; focus "$(win '^Run As$')"; key Return; fi
  wait_marker 120 "$marker" 10 "ran the program"
  settle 2 30; shot ran
}
TIMEOUT[eclipse_cdt]=600
