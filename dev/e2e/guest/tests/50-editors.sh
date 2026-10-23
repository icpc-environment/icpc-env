# Text editors: open a C++ file, check it's syntax highlighted (several
# distinct colours in the window), append a line with the editor's own keys,
# save, and check the line reached the disk.

EDIT_DIR=$C/e2e/editors

editor_source() {  # NAME -> path
  local f=$EDIT_DIR/e2e-$1.cpp
  put "$f" <<'EOF'
#include <bits/stdc++.h>
using namespace std;

// Sum of the first n squares
int main() {
    long long n, total = 0;
    cin >> n;
    for (long long i = 1; i <= n; i++) {
        total += i * i;
    }
    string label = "total";
    cout << label << ": " << total << " " << 3.14 << endl;
    return 0;
}
EOF
  echo "$f"
}

# editor NAME STYLE TITLE_REGEX [CLASS] -- CMD...   (STYLE: gui, vim or emacs)
editor() {
  local name=$1 style=$2 title=$3 cls=""; shift 3
  if [[ $1 != -- ]]; then cls=$1; shift; fi
  shift
  local f w hues
  f=$(editor_source "$name")
  launch "ed-$name" "$@" "$f"
  w=$(wait_win 90 "$title" "$cls") || return
  maximize "$w"; settle 2 60
  # Some editors start highlighting a moment after drawing the text
  sleep 2
  shot "$name-open"
  hues=$(X python3 -I "$E2E/colors.py" "$w")
  # Terminal vim/nvim colour only some tokens (nvim's default scheme just strings);
  # plain text in a terminal shows none
  local min=3; [[ $cls == xfce4-terminal ]] && min=1
  if (( hues >= min )); then pass "$name: syntax highlighted ($hues colours)"; else fail "$name: looks unhighlighted ($hues colours)"; fi
  focus "$w"
  case $style in
    gui) key ctrl+End; key Return; typ "// edited by $name"; key ctrl+s ;;
    vim) key Escape; typ "Go// edited by $name"; key Escape; typ ":w"; key Return ;;
    emacs) key ctrl+End; key Return; typ "// edited by $name"; key ctrl+x ctrl+s ;;
  esac
  if wait_for 15 grep -q "// edited by $name" "$f"; then pass "$name: edited and saved"; else fail "$name: the edit never reached $f"; fi
  shot "$name-saved"
  close_win "$w"; sleep 2
}

t_editors() {
  editor kate gui 'e2e-kate\.cpp' -- kate
  editor gedit gui 'e2e-gedit\.cpp' -- gedit
  editor mousepad gui 'e2e-mousepad\.cpp' -- mousepad
  editor geany gui 'e2e-geany\.cpp' -- geany
  editor gvim vim 'e2e-gvim\.cpp' -- gvim
  editor nvim-qt vim '' nvim-qt -- nvim-qt
  editor emacs emacs 'e2e-emacs\.cpp' -- emacs
  editor vim vim 'e2e-vim\.cpp|VIM' xfce4-terminal -- xfce4-terminal --maximize -x vim
  editor nvim vim '' xfce4-terminal -- xfce4-terminal --maximize -x nvim
}
TIMEOUT[editors]=900

t_codelite() {
  local f w
  f=$(editor_source codelite)
  launch codelite codelite "$f"
  w=$(wait_win 120 'e2e-codelite' codelite) || return
  settle 3 60
  # First launch runs a setup wizard: "Not this time!"
  if has_win '^Welcome!$'; then
    shot wizard; note "CodeLite's first launch shows a setup wizard; skipped it"
    focus "$(win '^Welcome!$')"; key Escape; sleep 2
  fi
  maximize "$w"; settle 3 60; sleep 2
  shot open
  local hues; hues=$(X python3 -I "$E2E/colors.py" "$w")
  (( hues >= 3 )) && pass "codelite: opened a C++ file, highlighted ($hues colours)" || fail "codelite: looks unhighlighted ($hues colours)"
}
TIMEOUT[codelite]=300
