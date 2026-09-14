#!/bin/bash
# Checks for the course site (course/), which is the only multi-language surface with moving parts.
#
# The one failure this suite exists to prevent: the scenario data in data*.js is Russian, and each
# locale ships an override file that replaces those strings. A key the override forgets falls back
# to *Russian*, not to English - so a Japanese page silently grows a Russian sentence and nobody
# notices until a reader files an issue. The check is blunt and total: apply the override, then
# assert not one Cyrillic character survives anywhere in the data.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/../course"
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip(){ SKIP=$((SKIP+1)); echo "  skip $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== locales declared in app.js match what is on disk"
LOCALES="$(python3 - "$C/app.js" <<'PY'
import re,sys
src=open(sys.argv[1],encoding='utf-8').read()
m=re.search(r'const LOCALES\s*=\s*\[(.*?)\];',src,re.S)
print(' '.join(re.findall(r"code:\s*'([^']+)'",m.group(1))) if m else '')
PY
)"
check "app.js declares a LOCALES list" "[ -n '$LOCALES' ]"
check "en is in LOCALES" "echo '$LOCALES' | grep -qw en"

for L in $LOCALES; do
  if [ "$L" = en ]; then PAGE="$C/index.html"; else PAGE="$C/$L/index.html"; fi
  check "locale $L has a page" "[ -f '$PAGE' ]"
  [ -f "$PAGE" ] || continue
  check "locale $L page declares lang=\"$L\"" "grep -q '<html lang=\"$L\">' '$PAGE'"
done

# the other direction: a locale folder that exists but nobody linked to it
for D in "$C"/*/; do
  L="$(basename "$D")"
  [ -f "$D/index.html" ] || continue
  check "locale folder $L is listed in LOCALES" "echo '$LOCALES' | grep -qw -- '$L'"
done

echo "== no Russian leaks through a locale override"
if command -v node >/dev/null 2>&1; then
  for L in $LOCALES; do
    [ "$L" = ru ] && continue           # ru is the base language of data*.js, Cyrillic is correct there
    OV="$C/$L.js"
    if [ ! -f "$OV" ]; then bad "locale $L has an override file $L.js"; continue; fi
    LEFT="$(node -e '
      const fs=require("fs"),vm=require("vm"),ctx={window:{},document:{}};vm.createContext(ctx);
      for(const f of ["data.js","data2.js","data3.js",process.argv[1]])
        vm.runInContext(fs.readFileSync(require("path").join(process.argv[2],f),"utf8"),ctx);
      const cyr=/[Ѐ-ӿ]/;let n=0,first="";
      (function walk(o,p){if(o===null||typeof o!=="object")return;
        for(const k of Object.keys(o)){const v=o[k];
          if(typeof v==="string"){if(cyr.test(v)){n++;if(!first)first=p+"."+k+" = "+v.slice(0,60);}}
          else if(typeof v==="object")walk(v,p+"."+k);}})(ctx.window.COURSE,"C");
      console.log(n+(first?"  first: "+first:""));
    ' "$L.js" "$C" 2>&1)"
    if [ "${LEFT%% *}" = "0" ]; then ok "locale $L override leaves no Cyrillic in the data"
    else bad "locale $L override leaves Cyrillic in the data: $LEFT"; fi
  done
else
  skip "Cyrillic-leak check (node not installed; it is the only check here that needs it)"
fi

echo "== player chrome (window.LR_I18N) is complete on every locale but ru"
# The keys have to be read with the string literals respected: a value like
# 'a turn: the human's request' contains a colon, and a naive regex reads "turn" as a key.
i18n_keys(){ python3 - "$1" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
i=src.find('window.LR_I18N')
if i<0: print(''); raise SystemExit
i=src.index('{',i); depth=0; keys=[]; tok=''; quote=None; esc=False
for ch in src[i:]:
    if quote:
        if esc: esc=False
        elif ch=='\\': esc=True
        elif ch==quote: quote=None
        continue
    if ch in '\'"`': quote=ch; tok=''; continue
    if ch in '{[': depth+=1; tok=''; continue
    if ch in '}]':
        depth-=1; tok=''
        if depth==0: break
        continue
    if ch==':' and depth==1 and tok.strip(): keys.append(tok.strip())
    if ch.isalnum() or ch=='_': tok+=ch
    elif ch==':' or ch==',': tok=''
print(' '.join(sorted(set(keys))))
PY
}
EN_KEYS="$(i18n_keys "$C/index.html")"
check "the English page sets LR_I18N" "[ -n '$EN_KEYS' ]"
for L in $LOCALES; do
  case "$L" in en|ru) continue ;; esac   # en is the reference, ru uses app.js's built-in defaults
  PAGE="$C/$L/index.html"; [ -f "$PAGE" ] || continue
  KEYS="$(i18n_keys "$PAGE")"
  check "locale $L sets the same LR_I18N keys as English" "[ '$KEYS' = '$EN_KEYS' ]"
done

echo "== CJK locales get a font stack (Geist carries no Han or kana glyphs)"
for L in $LOCALES; do
  case "$L" in ja|zh-CN|zh-TW|ko) ;; *) continue ;; esac
  check "style.css scopes --sans for lang=\"$L\"" "grep -q 'html\[lang=\"$L\"\]' '$C/style.css'"
done

echo
echo "course: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
