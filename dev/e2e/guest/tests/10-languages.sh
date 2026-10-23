# Command-line toolchains, as a contestant would use them from a terminal

lang_sources() {
  local d=$WORK/lang
  put $d/hello.c <<'EOF'
#include <stdio.h>
int main(void) { int n; if (scanf("%d", &n) != 1) return 1; printf("c %d\n", n * 2); return 0; }
EOF
  put $d/hello.cpp <<'EOF'
#include <bits/stdc++.h>
int main() { int n; std::cin >> n; std::vector<int> v(n); std::iota(v.begin(), v.end(), 1);
  std::cout << "cpp " << std::accumulate(v.begin(), v.end(), 0) << "\n"; }
EOF
  put $d/Hello.java <<'EOF'
import java.util.*;
public class Hello { public static void main(String[] a) { int n = new Scanner(System.in).nextInt(); System.out.println("java " + n * 2); } }
EOF
  put $d/hello.kt <<'EOF'
fun main() { val n = readLine()!!.trim().toInt(); println("kotlin ${n * 2}") }
EOF
  put $d/hello.py <<'EOF'
n = int(input())
print("python", n * 2)
EOF
}

# lang NAME "COMMAND" EXPECTED: run COMMAND as contestant in $WORK/lang with 21 on stdin
lang() {
  local got
  got=$(cd $WORK/lang && echo 21 | asc timeout 120 bash -c "$2" 2>&1 | tail -1)
  if [[ $got == "$3" ]]; then pass "$1: $3"; else fail "$1: wanted '$3', got '$got'"; fi
}

t_languages() {
  lang_sources
  lang gcc 'gcc -O2 -o c hello.c && ./c' 'c 42'
  lang g++ 'g++ -O2 -o cpp hello.cpp && ./cpp' 'cpp 231'
  lang java 'javac Hello.java && java Hello' 'java 42'
  lang kotlin 'kotlinc hello.kt -include-runtime -d hello.jar 2>/dev/null && java -jar hello.jar' 'kotlin 42'
  lang python3 'python3 hello.py' 'python 42'
  lang pypy3 'pypy3 hello.py' 'python 42'
}
TIMEOUT[languages]=600

# The judge-equivalent compile/run scripts from /icpc/config.json's language_scripts
t_contest_scripts() {
  lang_sources
  local l
  for l in $(cat /icpc/supported_languages); do
    command -v compile$l >/dev/null || { fail "no compile$l script"; continue; }
  done
  lang 'compilec/runc' 'rm -f a.out && compilec hello.c && runc' 'c 42'
  lang 'compilecpp/runcpp' 'rm -f a.out && compilecpp hello.cpp && runcpp' 'cpp 231'
  lang 'compilejava/runjava' 'compilejava Hello.java && runjava Hello' 'java 42'
  lang 'compilekotlin/runkotlin' 'compilekotlin hello.kt 2>/dev/null && runkotlin HelloKt' 'kotlin 42'
  lang 'compilepython3/runpython3' 'compilepython3 hello.py && runpython3 hello.py' 'python 42'
  # gdb and valgrind on a debug build
  local got
  put $WORK/lang/dbg.c <<'EOF2'
#include <stdio.h>
int main(void) {
    int total = 0;
    for (int i = 1; i <= 4; i++)
        total += i;
    printf("%d\n", total);
    return 0;
}
EOF2
  got=$(cd $WORK/lang && asc bash -c 'gcc -g -O0 -o cg dbg.c && gdb -q -batch -ex "break 6" -ex run -ex "print total" ./cg' 2>&1 | grep -E '^\$1 =')
  [[ $got == '$1 = 10' ]] && pass "gdb breakpoint and print" || fail "gdb: got '$got'"
  if command -v valgrind >/dev/null; then
    got=$(cd $WORK/lang && asc valgrind -q --error-exitcode=9 ./cg 2>&1); [[ $? == 0 ]] && pass "valgrind clean run" || fail "valgrind: $got"
  else
    note "valgrind not installed"
  fi
}
TIMEOUT[contest_scripts]=600
