# Desktop apps, Firefox (DevDocs, the squid block page) and the submit client

t_terminals() {
  local t marker
  for t in xfce4-terminal konsole alacritty kitty ghostty; do
    marker=$WORK/term-$t.out; rm -f "$marker"
    command -v $t >/dev/null || { fail "$t not installed"; continue; }
    case $t in
      konsole) launch "term-$t" konsole -e bash -c "echo ok > $marker; sleep 6" ;;
      ghostty) launch "term-$t" ghostty -e bash -c "echo ok > $marker; sleep 6" ;;
      xfce4-terminal) launch "term-$t" xfce4-terminal -x bash -c "echo ok > $marker; sleep 6" ;;
      *) launch "term-$t" $t -e bash -c "echo ok > $marker; sleep 6" ;;
    esac
    if wait_for 60 grep -qx ok "$marker"; then pass "$t: opened and ran a command"; else fail "$t: never ran its command"; fi
    sleep 1; shot "$t"
    pkill -u contestant -f "[${t:0:1}]${t:1}" ; sleep 1
  done
}
TIMEOUT[terminals]=400

t_calculator() {
  launch calc mate-calc
  local w; w=$(wait_win 60 'Calculator' ) || return
  settle 2 30
  focus "$w"; typ '6*7'; key Return; sleep 1
  shot result
  pass "mate-calc opened; 6*7 typed (check the screenshot shows 42)"
}

t_pdf_viewer() {
  local src=$WORK/pdf/sample.cpp ps=$WORK/pdf/sample.ps pdf=$WORK/pdf/sample.pdf
  editor_source pdf >/dev/null
  asc mkdir -p $WORK/pdf
  asc cp "$EDIT_DIR/e2e-pdf.cpp" "$src"
  asc bash -c "/icpc/scripts/printfile --output=$ps $src >/dev/null && ps2pdf $ps $pdf" \
    && pass "made a PDF with printfile --output and ps2pdf" || { fail "couldn't make a PDF"; return; }
  launch pdf mupdf "$pdf"
  local w; w=$(wait_win 60 'sample\.pdf') || return
  maximize "$w"; settle 2 30
  shot open
  pass "mupdf opened sample.pdf"
}

t_file_manager() {
  launch thunar thunar "$C"
  local w; w=$(wait_win 60 'contestant|Home') || return
  settle 2 30; shot open
  pass "thunar opened the home directory"
  close_win "$w"
}

# Open URL in the contestant's running Firefox (it autostarts) and wait for a title
firefox_open() {  # URL TITLE_REGEX
  pgrep -u contestant -x firefox >/dev/null || { launch firefox firefox; wait_win 90 'Mozilla Firefox' >/dev/null; settle 3 60; }
  launch "ff-$RANDOM" firefox --new-tab "$1"
  local w; w=$(wait_win 60 "$2.*Mozilla Firefox") || return 1
  maximize "$w"; settle 2 30
  echo "$w"
}

# Fetch a URL as contestant, through the proxy the way Firefox goes
contestant_curl() {
  asc curl -s -m 20 --proxy http://localhost:3128/ "$@"
}

t_devdocs() {
  local page
  page=$(contestant_curl https://devdocs/) && [[ $page == *DevDocs* ]] \
    && pass "https://devdocs/ answers through the proxy" || fail "https://devdocs/ didn't answer: ${page:0:200}"
  firefox_open https://devdocs/ 'DevDocs' >/dev/null && pass "Firefox shows DevDocs" || return
  shot home
  # A page from each language's docs, which live in the browser's offline store
  local doc
  for doc in 'cpp/container/vector|vector' 'c/io/fprintf|printf' 'openjdk~25/java.base/java/util/arraylist|ArrayList' \
             'python~3.11/library/collections|collections' 'kotlin~2.4/api/core/kotlin-stdlib/kotlin.collections/-mutable-list/index|MutableList'; do
    firefox_open "https://devdocs/${doc%%|*}" "${doc##*|}" >/dev/null && pass "DevDocs page ${doc%%|*}"
    shot "$(echo "${doc%%|*}" | tr '/~' '__')"
  done
  # The toolbar bookmark and the search engine both point at devdocs
  grep -q 'https://devdocs' /usr/lib/firefox/distribution/policies.json && pass "Firefox policies point at https://devdocs" || fail "no devdocs in Firefox policies"
}
TIMEOUT[devdocs]=400

t_web_filter() {
  local page
  page=$(contestant_curl https://www.google.com/)
  [[ $page == *'Access Denied'* ]] && pass "google.com through the proxy gets the Access Denied page" || fail "google.com: ${page:0:200}"
  firefox_open https://www.google.com/ '' >/dev/null
  sleep 3; shot google
  local title; title=$(X xdotool getactivewindow getwindowname)
  note "Firefox title for google.com: $title"
  # Direct connections, and DNS, are blocked for contestant
  if asc curl -s -m 10 --noproxy '*' -o /dev/null https://www.google.com/; then fail "contestant reached google.com without the proxy"; else pass "direct connections are blocked"; fi
  if asc timeout 10 getent hosts example.com >/dev/null; then fail "contestant can resolve example.com"; else pass "DNS lookups are blocked"; fi
  # The contest's own site goes through
  local home; home=$(jq -r '.firefox_policies.Homepage.URL // empty' /icpc/config.json)
  if [[ -n $home ]]; then
    page=$(contestant_curl -o /dev/null -w '%{http_code}' "$home")
    [[ $page =~ ^[23] || $page == 404 ]] && pass "homepage $home answers ($page)" || fail "homepage $home: HTTP $page"
    contestant_curl "$home" | grep -q 'Access Denied' && fail "homepage $home is blocked"
  fi
}
TIMEOUT[web_filter]=300

t_submit() {
  local out rc
  command -v submit >/dev/null || { fail "no submit command"; return; }
  note "submit -> $(readlink -f "$(command -v submit)")"
  out=$(asc bash -lc 'submit --help' 2>&1); rc=$?
  (( rc == 0 )) && pass "submit --help works" || fail "submit --help exited $rc: ${out:0:200}"
  asc mkdir -p $WORK/submit
  asc bash -c "printf 'int main(){}\n' > $WORK/submit/hello.cpp"
  out=$(cd $WORK/submit && asc bash -lc 'submit -p hello hello.cpp' </dev/null 2>&1); rc=$?
  if (( rc != 0 )) && grep -qi kattisrc <<<"$out"; then
    pass "submit without credentials explains how to get a kattisrc"
  else
    fail "submit without credentials: exit $rc, ${out:0:300}"
  fi
  printf '%s\n' "$out" > "$OUT/$CURRENT-output.txt"
}

# IDE shortcuts the window manager must not take: Run/Debug/Build/Stop and
# friends in VS Code, the JetBrains IDEs and Eclipse
t_ide_shortcuts() {
  local line combo
  declare -A uses=(
    [F5]="VS Code debug" [ctrl+F5]="VS Code run without debugging" [shift+F5]="VS Code stop"
    [F9]="breakpoint (VS Code), resume (JetBrains)" [ctrl+F9]="JetBrains build" [ctrl+F2]="JetBrains stop"
    [ctrl+F8]="JetBrains toggle breakpoint" [shift+F10]="JetBrains run" [shift+F9]="JetBrains debug"
    [ctrl+shift+F10]="JetBrains run this file" [alt+F7]="JetBrains find usages" [alt+F8]="JetBrains evaluate expression"
    [alt+F9]="JetBrains run to cursor" [alt+F10]="JetBrains show execution point" [ctrl+F11]="Eclipse run"
    [F11]="Eclipse debug, VS Code step into" [F10]="VS Code step over" [ctrl+F10]="VS Code run to cursor"
    [ctrl+b]="Eclipse build" [ctrl+shift+b]="VS Code build task"
  )
  while read -r line; do
    combo=${line#* }
    if [[ $line == ok* ]]; then pass "$combo reaches apps (${uses[$combo]})"; else fail "$combo is taken by the window manager (${uses[$combo]})"; fi
  done < <(X python3 -I "$E2E/keycheck.py" "${!uses[@]}")
}
