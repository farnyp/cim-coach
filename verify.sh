#!/usr/bin/env bash
# verify.sh <index.html> — gate before every push. Exits non-zero on any failure.
set -uo pipefail
F="${1:?usage: verify.sh <index.html>}"
fail=0
say(){ printf '%-38s %s\n' "$1" "$2"; }
bad(){ say "$1" "FAIL — $2"; fail=1; }
ok(){  say "$1" "ok${2:+ — $2}"; }

# 1. script tag balance (counted independently of any parse)
o=$(grep -o '<script' "$F" | wc -l | tr -d ' ')
c=$(grep -o '</script>' "$F" | wc -l | tr -d ' ')
[ "$o" = "$c" ] && ok "script tags balanced" "$o/$c" || bad "script tags balanced" "$o open, $c close"

# 2. no credential in the public page
if grep -qE 'github_pat_[A-Za-z0-9_]{20,}' "$F"; then bad "no token in page" "PAT found"; else ok "no token in page"; fi

# 3. storage key frozen
grep -q "const KEY='cim-coach-state'" "$F" && ok "storage key frozen" || bad "storage key frozen" "cim-coach-state missing"

# 4. every \$('id') resolves to an element id present in the page
python3 - "$F" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
ids=set(re.findall(r'\bid="([^"]+)"',s))
refs=sorted(set(re.findall(r"\$\('([^']+)'\)",s)))
missing=[r for r in refs if r not in ids]
print('%-38s %s'%('$(id) references resolve',
      'ok — %d refs'%len(refs) if not missing else 'FAIL — missing: '+', '.join(missing)))
sys.exit(1 if missing else 0)
PY
[ $? -ne 0 ] && fail=1

# 5. JS syntax — parse the script bodies, never split on the tag being checked
python3 - "$F" > /tmp/_body.js <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
print('\n;\n'.join(m.group(1) for m in re.finditer(r'<script[^>]*>(.*?)</script>',s,re.S)))
PY
if node --check /tmp/_body.js 2>/tmp/_err; then ok "JS parses"; else bad "JS parses" "$(head -3 /tmp/_err|tr '\n' ' ')"; fi

# 6. PLANVER present and numeric
pv=$(grep -oE 'const PLANVER=[0-9]+' "$F" | grep -oE '[0-9]+$')
[ -n "$pv" ] && ok "PLANVER" "$pv" || bad "PLANVER" "not found"

# 7. build stamp present
grep -q 'build 20' "$F" && ok "build stamp" "$(grep -o 'build 20[^<]*' "$F" | head -1)" || bad "build stamp" "missing"

echo
[ $fail -eq 0 ] && echo "VERIFY PASSED" || echo "VERIFY FAILED"
exit $fail
