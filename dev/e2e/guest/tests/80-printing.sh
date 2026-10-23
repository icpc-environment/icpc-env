# Printing. Only runs when asked for (`print`), since on a team machine it
# uses the real printer. A handful of pages: printfile's default two-up
# landscape with awkward characters, a one-column portrait file, plain lp, and
# printing from an app's print dialog.

print_samples() {
  local d=$WORK/print
  asc mkdir -p $d
  put $d/special_chars.cpp <<'EOF'
// printfile test: two columns, landscape, syntax highlighted, UTF-8
// Accents: café naïve résumé façade jalapeño Ångström Øresund Łódź
// Greek: α β γ δ ε π Σ Ω   Cyrillic: Привет мир   CJK: 你好世界 こんにちは 안녕하세요
// Maths: ≤ ≥ ≠ ≈ ∞ ∑ ∏ √ ∫ ∂ ∀ ∃ ∈ ∉ ⊂ ∪ ∩ ¬ ∧ ∨ ⊕ → ← ↔ ⇒ ±  ×  ÷  ° ‰
// Punctuation: “double” ‘single’ «guillemets» — em dash – en dash … bullet • ¶ § † ‡ © ® ™ €£¥
// Box drawing: ┌─┬─┐ │ │ │ ├─┼─┤ └─┴─┘   Emoji (may show as boxes): 😀 🎈 ✓ ✗
#include <bits/stdc++.h>
using namespace std;

struct Edge { int to; long long w; };

int main() {
	// a tab-indented line, then a very long line that has to wrap or be cut: 0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
	int n, m;
	cin >> n >> m;
	vector<vector<Edge>> g(n);
	for (int i = 0; i < m; i++) {
		int a, b; long long w;
		cin >> a >> b >> w;
		g[a].push_back({b, w});
		g[b].push_back({a, w});
	}
	vector<long long> dist(n, LLONG_MAX);
	priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
	dist[0] = 0; pq.push({0, 0});
	while (!pq.empty()) {
		auto [d, u] = pq.top(); pq.pop();
		if (d != dist[u]) continue;
		for (auto [v, w] : g[u])
			if (dist[u] + w < dist[v]) { dist[v] = dist[u] + w; pq.push({dist[v], v}); }
	}
	for (int i = 0; i < n; i++) cout << i << ": " << (dist[i] == LLONG_MAX ? -1 : dist[i]) << "\n";
	string s = "tab\there, backslash \\ quote \" percent % dollar $ braces {} <angle> &amp;";
	cout << s << endl;
}
EOF
  put $d/Portrait.java <<'EOF'
// printfile -1 --portrait: one column, portrait
import java.util.*;

public class Portrait {
    public static void main(String[] args) {
        Scanner in = new Scanner(System.in);
        int n = in.nextInt();
        long[] fib = new long[Math.max(2, n + 1)];
        fib[1] = 1;
        for (int i = 2; i <= n; i++) fib[i] = fib[i - 1] + fib[i - 2];
        System.out.println("fib(" + n + ") = " + fib[n] + " — ünïcödé ✓");
    }
}
EOF
  put $d/plain-lp.txt <<'EOF'
Sent with plain `lp`, no printfile: icpc-printer should still stamp the team on it.
Line two. Ünïcödé: ✓ → π
EOF
  put $d/from-gedit.py <<'EOF'
# Printed from gedit's print dialog (Ctrl+P)
def solve(xs):
    return sorted(set(xs))

print(solve([3, 1, 2, 3, "naïve"][:4]))
EOF
}

# Pages in a PostScript file
ps_pages() { grep -c '^%%Page:' "$1"; }

x_print() {
  print_samples
  local d=$WORK/print pages=0 p out
  lpstat -d 2>&1 | tee -a "$OUT/$CURRENT-lpstat.txt" >/dev/null
  lpstat -v >> "$OUT/$CURRENT-lpstat.txt" 2>&1
  local before; before=$(ls /var/lib/icpc-printer 2>/dev/null | wc -l)
  # Count first, so this never prints more than intended
  asc /icpc/scripts/printfile --output=$d/a.ps $d/special_chars.cpp >/dev/null
  asc /icpc/scripts/printfile -1 --portrait --output=$d/b.ps $d/Portrait.java >/dev/null
  p=$(( $(ps_pages $d/a.ps) + $(ps_pages $d/b.ps) + 2 ))
  note "about to print about $p pages"
  (( p <= 9 )) || { fail "would print $p pages; not printing"; return; }
  out=$(cd $d && asc /icpc/scripts/printfile special_chars.cpp 2>&1); log "$out"
  [[ $out == *"sent to the printer"* ]] && pass "printfile (2-up landscape): $out" || fail "printfile: $out"
  out=$(cd $d && asc /icpc/scripts/printfile -1 --portrait Portrait.java 2>&1); log "$out"
  [[ $out == *"sent to the printer"* ]] && pass "printfile -1 --portrait: $out" || fail "printfile -1 --portrait: $out"
  out=$(cd $d && asc lp plain-lp.txt 2>&1)
  [[ $out == *"request id"* ]] && pass "lp: $out" || fail "lp: $out"
  # gedit's print dialog, printing to the default printer
  launch print-gedit gedit $d/from-gedit.py
  local w; w=$(wait_win 60 'from-gedit\.py') || return
  settle 2 30; focus "$w"; key ctrl+p
  local pd; pd=$(wait_win 30 '^Print$') || return
  settle 2 30; shot gedit-print-dialog
  focus "$pd"; key Return
  wait_for 30 no_win '^Print$' && pass "printed from gedit's print dialog" || fail "gedit's print dialog didn't go away"
  sleep 5
  # Every job should leave the local queue and land in icpc-printer's archive
  if wait_for 180 bash -c '[[ -z $(lpstat -o 2>/dev/null) ]]'; then pass "the print queue drained"; else fail "jobs still queued: $(lpstat -o | tr '\n' ';')"; fi
  local after; after=$(ls /var/lib/icpc-printer 2>/dev/null | wc -l)
  (( after >= before + 4 )) && pass "icpc-printer archived $((after - before)) new jobs" || fail "icpc-printer archive went from $before to $after entries"
  lpstat -W completed -o >> "$OUT/$CURRENT-lpstat.txt" 2>&1
  journalctl -u icpc-printer --since '-15 min' --no-pager > "$OUT/$CURRENT-icpc-printer.log"
}
TIMEOUT[print]=600
