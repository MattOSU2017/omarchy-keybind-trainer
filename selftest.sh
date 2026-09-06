#!/usr/bin/env bash
# Acceptance suite for omarchy-keybind-trainer.
#
# Everything here runs on ANY Omarchy machine. It asserts invariants, never
# counts or particular bindings: an earlier version checked for one specific
# machine's own SUPER+Q, its own panel tile and its own count of installed
# themes, so the suite could only ever pass where it was written.
#
# Safe to run any time. The mutating checks create their own scratch binding
# and remove it again; no binding of yours is ever suspended.
#
#   selftest.sh           portable suite
#   selftest.sh --local   ...plus checks specific to the development machine
set -uo pipefail

LOCAL=0
[ "${1:-}" = "--local" ] && LOCAL=1

BIN="${OMARCHY_KEYBIND_TRAINER_BIN:-$(command -v omarchy-keybind-trainer || echo "$HOME/.local/bin/omarchy-keybind-trainer")}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8489                      # not the real one; never collides with a live drill
SCRATCH="SUPER + CTRL + ALT + SHIFT + F24"

PASS=0 FAIL=0 WARN=0
ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS+1)); }
wr(){ printf '  \033[33mwarn\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }
have(){ command -v "$1" >/dev/null 2>&1; }

for tool in jq python3 hyprctl; do
  have "$tool" || { echo "selftest needs $tool"; exit 2; }
done

TMP=$(mktemp -d)
SRVPID=""
cleanup(){
  [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
  hyprctl eval "hl.unbind(\"$SCRATCH\")" >/dev/null 2>&1
  hyprctl reload >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---------------------------------------------------------------- install
echo "== install =="
[ -x "$BIN" ] && ok "launcher is executable" || no "launcher missing: $BIN"
python3 -c "import ast;ast.parse(open('$BIN').read())" 2>/dev/null \
  && ok "launcher parses" || no "launcher has a syntax error"
APP=$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("t", sys.argv[1]).load_module()
p = m.find_data("app.html")
print(p or "")
PY
)
[ -n "$APP" ] && ok "app.html found ($APP)" || no "app.html not found in any data dir"
python3 -c "
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
sys.exit(0 if m._load_theme_fn() else 1)" 2>/dev/null \
  && ok "theme resolver found" || no "theme resolver not found in any lib dir"

# ---------------------------------------------------------------- deck
echo "== deck =="
DECK="$TMP/deck.json"
if ! "$BIN" --print-deck > "$DECK" 2>"$TMP/deck.err"; then
  no "--print-deck failed: $(head -1 "$TMP/deck.err")"
  echo; printf '\033[31m%d passed, %d failed\033[0m\n' "$PASS" "$((FAIL))"; exit 1
fi
N=$(jq length "$DECK")
[ "$N" -gt 0 ] && ok "deck built ($N cards)" || no "deck is empty"
chk "no keypad clones survive" \
  "$(jq '[.[]|select(.keys[]|test("KP_|code:(79|8[0-9]|9[01])"))]|length' "$DECK")" 0
chk "every card has at least one key" "$(jq '[.[]|select((.keys|length)==0)]|length' "$DECK")" 0
chk "every card has a category" "$(jq '[.[]|select(.category==null or .category=="")]|length' "$DECK")" 0
chk "every card has an action" "$(jq '[.[]|select(.action==null or .action=="")]|length' "$DECK")" 0
chk "no duplicate cards" "$(jq '[.[].id]|length - (unique|length)' "$DECK")" 0
chk "numeric families are collapsed" \
  "$(jq '[.[]|select(.action|test("^(Switch to|Move window (silently )?to) workspace [0-9]+$"))]|length' "$DECK")" 0
# Live-fire is the mechanic; if nothing qualifies the tool does nothing.
L=$(jq '[.[]|select(.live)]|length' "$DECK")
[ "$L" -gt 0 ] && ok "$L of $N cards are live-fireable" || no "nothing is live-fireable"
# Every combo on a live card must be pressable AND suspendable - accepting a
# card because one alias qualified left the others live, and a collapsed
# family card carries ten combos.
chk "a live card has every combo pressable" \
  "$(jq '[.[]|select(.live and ([.codes[]|select(.code==null)]|length)>0)]|length' "$DECK")" 0
chk "media keys are never live-fireable" \
  "$(jq '[.[]|select(.live and (.keys[]|test("XF86")))]|length' "$DECK")" 0
chk "mouse bindings are never live-fireable" \
  "$(jq '[.[]|select(.live and (.keys[]|test("mouse")))]|length' "$DECK")" 0
chk "CTRL+ALT+DELETE is never live-fireable" \
  "$(jq '[.[]|select(.live and (.keys[]|test("CTRL \\+ ALT \\+ DELETE")))]|length' "$DECK")" 0
# The deny list is a policy on the description, so it holds whatever the user
# has bound lock or power to.
chk "locking and power are never live-fireable" \
  "$(jq '[.[]|select(.live and (.action|test("(?i)\\b(lock|power|log ?out|reboot|shut ?down|close all)\\b")))]|length' "$DECK")" 0

# ---------------------------------------------------------------- attribution
echo "== category attribution =="
# The bug this guards: category_for() grepped the Lua sources for the
# description and did not skip comments, so Omarchy's own commented-out
# examples in bindings.lua tagged upstream bindings as the user's own. That
# misfired on a clean install, not just a customised one.
COMMENTED=$(python3 - <<'PY'
import re, json, pathlib
p = pathlib.Path.home() / ".config/hypr/bindings.lua"
if not p.is_file():
    print(""); raise SystemExit
out = []
for line in p.read_text(errors="replace").splitlines():
    if line.lstrip().startswith("--"):
        m = re.search(r'o\.bind\(\s*"[^"]*"\s*,\s*"([^"]+)"', line)
        if m:
            out.append(m.group(1))
print(json.dumps(out))
PY
)
if [ -z "$COMMENTED" ] || [ "$COMMENTED" = "[]" ]; then
  ok "no commented-out o.bind examples to confuse the tagger (skipped)"
else
  BAD=$(jq --argjson c "$COMMENTED" \
    '[.[]|select(.category=="Mine" and (.action as $a | $c|index($a)))]|length' "$DECK")
  chk "a commented-out example never tags a binding Mine" "$BAD" 0
fi
chk "strip_lua_comments leaves string literals alone" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
s = m.strip_lua_comments('o.bind(\"A\", \"keep -- this\", x)  -- drop this')
print('ok' if 'keep -- this' in s and 'drop this' not in s else 'bad')")" "ok"
chk "modifier order does not affect attribution" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
print('ok' if m.norm_combo('shift + super+A') == m.norm_combo('SUPER+SHIFT+a') == 'SUPER + SHIFT + A' else 'bad')")" "ok"

# ---------------------------------------------------------------- grammar
echo "== grammar =="
# The grammar must be DERIVED from whatever config it is handed. These checks
# feed it synthetic decks, so they fail if anyone ever hardcodes this author's
# keybindings into the rules.
chk "a modifier's meaning is read from the deck, not hardcoded" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
deck = [{'keys':['SUPER + CTRL + '+c],'action':'X','category':'Media'} for c in 'ABCDE']
r = m.derive_grammar(deck)
print('ok' if r.get('SUPER + CTRL',{}).get('label')=='media and hardware keys' else 'bad '+str(r))")" "ok"
chk "a mixed modifier set earns no rule" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
cats = ['Apps','Windows','System','Media','Clipboard']
deck = [{'keys':['SUPER + ALT + '+c],'action':'X','category':k} for c,k in zip('ABCDE',cats)]
print('ok' if 'SUPER + ALT' not in m.derive_grammar(deck) else 'bad')")" "ok"
chk "too few bindings is a coincidence, not a rule" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
deck = [{'keys':['SUPER + ALT + '+c],'action':'X','category':'Apps'} for c in 'AB']
print('ok' if not m.derive_grammar(deck) else 'bad')")" "ok"
chk "'Mine' never wins a modifier's meaning" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
deck = [{'keys':['SUPER + SHIFT + '+c],'action':'X','category':'Mine'} for c in 'ABCDEFG']
deck += [{'keys':['SUPER + SHIFT + '+c],'action':'X','category':'Apps'} for c in 'HIJ']
r = m.derive_grammar(deck).get('SUPER + SHIFT',{})
print('ok' if r.get('label')=='launch an app' else 'bad '+str(r))")" "ok"
chk "modifiers are named in binding order, not alphabetical" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
print(m.canonical_mods({'SHIFT','SUPER','CTRL','ALT'}))")" "SUPER + CTRL + ALT + SHIFT"
chk "a variant needs a shared word, not just a shared key" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
deck = [{'keys':['SUPER + SHIFT + B'],'action':'Browser','category':'Apps'},
        {'keys':['SUPER + ALT + SHIFT + B'],'action':'Browser (private)','category':'Apps'},
        {'keys':['SUPER + CTRL + ALT + B'],'action':'Bluetooth','category':'System'}]
m.annotate_grammar(deck)
linked = deck[1]['why']['variant'] is not None
unlinked = deck[2]['why']['variant'] is None
print('ok' if linked and unlinked else f'bad {linked} {unlinked}')")" "ok"
chk "the letter link finds the word it stands for" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
print('ok' if m.letter_link('G','Photo Gallery')=='Gallery'
      and m.letter_link('W','WhatsApp')=='WhatsApp'
      and m.letter_link('G','WhatsApp') is None else 'bad')")" "ok"
chk "a binding with no link at all is flagged as arbitrary" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
deck = [{'keys':['SUPER + SHIFT + Q'],'action':'Telegram','category':'Apps'}]
m.annotate_grammar(deck)
print('ok' if deck[0]['why']['odd'] else 'bad')")" "ok"
# On the live deck: every card carries a why, and the flagged set is a small
# minority. If most of the deck is "arbitrary" the derivation has broken.
chk "every card carries an explanation" \
  "$(jq '[.[]|select(.why==null)]|length' "$DECK")" 0
ODD=$(jq '[.[]|select(.why.odd)]|length' "$DECK")
TOT=$(jq 'length' "$DECK")
if [ "$ODD" -lt $((TOT / 3)) ]; then ok "$ODD of $TOT bindings are genuinely arbitrary"
else no "$ODD of $TOT flagged arbitrary - the grammar derivation is not working"; fi

# ---------------------------------------------------------------- suspend
echo "== suspend / restore round-trip =="
# On a scratch binding this suite creates, so no binding of yours is touched.
hyprctl eval "hl.bind(\"$SCRATCH\", hl.dsp.exec_cmd(\"true\"), { description = \"selftest scratch binding\" })" >/dev/null 2>&1
sleep 0.3
active(){ hyprctl binds 2>/dev/null | grep -c 'selftest scratch binding'; }
chk "scratch binding created" "$(active)" 1
# `arg:` is an internal Lua callback index that renumbers on every unbind.
hyprctl binds 2>/dev/null | grep -v $'^\targ:' > "$TMP/before"
hyprctl eval "hl.unbind(\"$SCRATCH\")" >/dev/null 2>&1
chk "hl.unbind via eval removes a binding" "$(active)" 0
hyprctl reload >/dev/null 2>&1; sleep 0.5
hyprctl binds 2>/dev/null | grep -v $'^\targ:' > "$TMP/after"
chk "reload leaves the scratch binding gone" "$(active)" 0
"$BIN" --restore >/dev/null 2>&1 && ok "--restore succeeds" || no "--restore failed"

# ---------------------------------------------------------------- server
echo "== server =="
"$BIN" --foreground --port "$PORT" >"$TMP/srv.log" 2>&1 &
SRVPID=$!
for _ in $(seq 1 30); do
  curl -sf "http://127.0.0.1:$PORT/whoami" >/dev/null 2>&1 && break
  sleep 0.3
done
if ! curl -sf "http://127.0.0.1:$PORT/whoami" >/dev/null 2>&1; then
  no "server did not come up on $PORT"
else
  ok "server came up on $PORT"
  chk "/whoami identifies the drill" \
    "$(curl -s "http://127.0.0.1:$PORT/whoami" | jq -r .app)" "omarchy-keybind-trainer"
  # A second launch must tell "already running" from "someone else's service".
  chk "port identity is checked, not just occupancy" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
print(m.port_owner($PORT))")" "ours"
  # The page carries its own deck and palette, resolved per request so a theme
  # switch shows up without a restart.
  curl -s "http://127.0.0.1:$PORT/" > "$TMP/page.html"
  chk "the page has no unsubstituted boot placeholder" \
    "$(grep -c '__BOOT__' "$TMP/page.html")" 0
  python3 - "$TMP/page.html" <<'PY' > "$TMP/boot.json"
import re, sys, json
h = open(sys.argv[1]).read()
m = re.search(r'const BOOT = (\{.*?\});\n', h, re.S)
print(m.group(1).replace('<\\/', '</') if m else '{}')
PY
  chk "the page is served with a deck" \
    "$( [ "$(jq '.deck|length' "$TMP/boot.json")" -gt 0 ] && echo yes || echo no)" "yes"
  chk "the page is served with a full palette" \
    "$(jq '.palette|length' "$TMP/boot.json")" 25
  chk "a healthy deck reports no status problem" "$(jq -r '.status' "$TMP/boot.json")" "null"
  # Any page in the browser is on loopback's client side, and /arm unbinds real
  # keybindings, so the origin has to be checked.
  chk "cross-origin POST is refused" "$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST -H 'Origin: http://evil.example' -H 'Content-Type: application/json' \
    -d '{"combo":"'"$SCRATCH"'"}' "http://127.0.0.1:$PORT/arm")" "403"
  chk "a rebound Host is refused" "$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST -H 'Host: evil.example' "http://127.0.0.1:$PORT/restore")" "403"
  chk "the deny policy is enforced server-side, not only in the deck" \
    "$(curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"combo":"SUPER + CTRL + P","action":"Power"}' "http://127.0.0.1:$PORT/arm" | jq -r .ready)" "false"

  # The heartbeat must report what the compositor actually has, not the
  # server's bookkeeping: Hyprland restores every binding on any config save,
  # and a question left on screen for a binding that came back fires for real.
  hyprctl eval "hl.bind(\"$SCRATCH\", hl.dsp.exec_cmd(\"true\"), { description = \"selftest scratch binding\" })" >/dev/null 2>&1
  sleep 0.3
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"combo":"'"$SCRATCH"'","action":"selftest scratch binding"}' \
    "http://127.0.0.1:$PORT/arm" >/dev/null
  chk "arming really unbinds it" "$(active)" 0
  chk "the heartbeat reports it suspended" \
    "$(curl -s "http://127.0.0.1:$PORT/ping" | jq -r '.suspended|index("'"$SCRATCH"'")!=null')" "true"
  # What a config save does to a *real* binding: it comes back while the
  # server still believes it is suspended. `hyprctl reload` cannot stand in
  # here - it deletes an eval-created binding rather than restoring it.
  hyprctl eval "hl.bind(\"$SCRATCH\", hl.dsp.exec_cmd(\"true\"), { description = \"selftest scratch binding\" })" >/dev/null 2>&1
  # Poll rather than sleep a fixed amount: hyprctl applies the bind
  # asynchronously, and a fixed wait made this check flaky about half the time.
  DETECT=false
  for _ in $(seq 1 20); do
    if [ "$(curl -s "http://127.0.0.1:$PORT/ping" | jq -r '.suspended|length')" = "0" ]; then
      DETECT=true; break
    fi
    sleep 0.3
  done
  chk "a binding restored underneath is no longer reported as held" "$DETECT" "true"

  # Progress must survive a file that is valid JSON of the wrong shape.
  curl -s -X POST "http://127.0.0.1:$PORT/restore" >/dev/null
  chk "restore clears the suspended set" \
    "$(curl -s "http://127.0.0.1:$PORT/ping" | jq -r '.suspended|length')" "0"
  chk "malformed progress does not break /progress" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
import json
orig = m.PROGRESS.read_text() if m.PROGRESS.exists() else None
bad = 0
for junk in ['null','[]','{\"x\":1}','not json','']:
    m.PROGRESS.write_text(junk)
    try:
        m.merge_progress({'bindings':{'K':{'seen':1,'right':1}}})
    except Exception:
        bad += 1
if orig is None: m.PROGRESS.unlink(missing_ok=True)
else: m.PROGRESS.write_text(orig)
print(bad)")" "0"
  kill "$SRVPID" 2>/dev/null; SRVPID=""
  sleep 0.5
fi

# ---------------------------------------------------------------- theme
echo "== theme resolver =="
python3 - <<'PY' > "$TMP/themes.txt"
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".local/lib/omarchy"))
for d in (Path("/usr/share/omarchy/themes"), Path.home() / ".config/omarchy/themes"):
    if not d.is_dir():
        continue
    for t in sorted(d.iterdir()):
        if t.is_dir():
            print(t)
PY
TN=0 TBAD=0 TEMPTY=0
while read -r theme; do
  [ -z "$theme" ] && continue
  TN=$((TN+1))
  R=$(python3 - "$theme" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".local/lib/omarchy"))
import omarchy_theme as t
d = Path(sys.argv[1])
if t.theme_source(d) is None:
    print("EMPTY"); raise SystemExit
t.THEME_DIR = d
try:
    p = t.theme_colors()
except Exception as e:
    print(f"THREW {e}"); raise SystemExit
floors = [("fg","card",4.5),("muted","card",3.0),("faint","card",2.2),
          ("accent","page",2.5),("on-accent","accent",4.5),
          ("ok","card",3.0),("bad","card",3.0),("warn","card",3.0)]
bad = [f"{a}/{b}={t.contrast(p[a],p[b]):.2f}<{m}"
       for a, b, m in floors if t.contrast(p[a], p[b]) < m]
print("OK" if not bad else "LOW " + " ".join(bad))
PY
)
  case "$R" in
    OK) ;;
    EMPTY) TEMPTY=$((TEMPTY+1)); echo "       empty theme dir: $(basename "$theme")" ;;
    *) TBAD=$((TBAD+1)); echo "       $(basename "$theme"): $R" ;;
  esac
done < "$TMP/themes.txt"
[ "$TN" -gt 0 ] && ok "$TN installed themes examined" || no "no themes found at all"
chk "every readable theme clears its contrast floors" "$TBAD" 0
# A theme dir with no colors.toml resolves to the built-in defaults and clears
# every contrast floor while showing the wrong colours - the themes most likely
# to be broken were the ones this gate passed most confidently. It is the
# theme that is broken, not the drill, so it warns rather than fails.
if [ "$TEMPTY" = 0 ]; then ok "every installed theme is readable"
else wr "$TEMPTY installed theme(s) have no colors.toml - the drill will show its fallback palette for them"; fi
chk "the active theme yields a full palette" "$(python3 -c "
import sys; sys.path.insert(0,'$HOME/.local/lib/omarchy')
from omarchy_theme import theme_colors; print(len(theme_colors()))")" "25"
chk "a short hex form does not throw" "$(python3 -c "
import sys; sys.path.insert(0,'$HOME/.local/lib/omarchy')
import omarchy_theme as t
print('ok' if t._hex('#abc')==(170,187,204) else 'bad')")" "ok"
# Every safety path has to work with the resolver gone.
chk "the drill falls back when the resolver is missing" "$(python3 -c "
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('t','$BIN').load_module()
m.LIB_DIRS = []; m._theme_fn = None
p = m.theme_colors()
print('ok' if len(p)==25 and p['accent']==m.FALLBACK_PALETTE['accent'] else 'bad')")" "ok"

# ---------------------------------------------------------------- crash
echo "== crash recovery =="
chk "the dead-man action checks the pid before reloading" "$(python3 -c "
from importlib.machinery import SourceFileLoader
import inspect
m = SourceFileLoader('t','$BIN').load_module()
s = inspect.getsource(m.arm_deadman)
print('ok' if 'kill -0' in s else 'bad')")" "ok"
chk "the marker path is shell-quoted" "$(python3 -c "
from importlib.machinery import SourceFileLoader
import inspect
m = SourceFileLoader('t','$BIN').load_module()
print('ok' if 'shlex.quote' in inspect.getsource(m.arm_deadman) else 'bad')")" "ok"
chk "a missing systemd degrades instead of throwing" "$(python3 -c "
from importlib.machinery import SourceFileLoader
import subprocess
m = SourceFileLoader('t','$BIN').load_module()
real = subprocess.run
subprocess.run = lambda *a, **k: (_ for _ in ()).throw(FileNotFoundError())
try:
    m.arm_deadman(); m.cancel_deadman(); print('ok')
except Exception as e:
    print('threw', e)
finally:
    subprocess.run = real")" "ok"
MARKER="$HOME/.local/state/omarchy/keybind-trainer/suspended"
[ -e "$MARKER" ] && no "a binding is left suspended right now" || ok "nothing left suspended"

# ---------------------------------------------------------------- drift
echo "== release drift =="
# The repo is the canonical home of both files. Two copies exist because the
# theme resolver is shared with omarchy-catalog; this check is what makes that
# divergence loud instead of silent.
for pair in "omarchy-keybind-trainer:$BIN" "omarchy_theme.py:$HOME/.local/lib/omarchy/omarchy_theme.py"; do
  name=${pair%%:*}; live=${pair#*:}
  if [ -f "$REPO/$name" ]; then
    if cmp -s "$REPO/$name" "$live"; then ok "$name matches the installed copy"
    else no "$name differs from $live - one of them is stale"; fi
  else
    ok "$name not in the repo yet (skipped)"
  fi
done

# ---------------------------------------------------------------- local
if [ "$LOCAL" = 1 ]; then
  echo "== this machine only =="
  grep -q 'learn.keybind-drill' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" 2>/dev/null \
    && ok "menu row present" || no "menu row missing"
  [ -s "$HOME/.local/share/applications/omarchy-keybind-trainer.desktop" ] \
    && ok ".desktop entry present" || no ".desktop entry missing"
  # Stated as invariants rather than by naming particular bindings: this
  # section used to assert one specific machine's tiles and overrides, which
  # put that config in a public repo and made --local fail for everyone else.
  M=$(jq '[.[]|select(.category=="Mine")]|length' "$DECK")
  [ "$M" -gt 0 ] && ok "$M bindings of your own are tagged Mine" \
                 || no "nothing tagged Mine - do you have bindings in ~/.config/hypr?"
  # The comment-matching bug: a description defined upstream must not be
  # claimed by a commented-out example in the user's own config.
  chk "no upstream binding is claimed by a commented-out example" "$(python3 -c "
import json, re, pathlib
deck = json.load(open('$DECK'))
p = pathlib.Path.home() / '.config/hypr/bindings.lua'
commented = set()
if p.is_file():
    for line in p.read_text(errors='replace').splitlines():
        if line.lstrip().startswith('--'):
            m = re.search(r'o\.bind\(\s*\"[^\"]*\"\s*,\s*\"([^\"]+)\"', line)
            if m: commented.add(m.group(1))
print(len([c for c in deck if c['action'] in commented and c['category'] == 'Mine']))")" "0"
  # Aliases merge whatever they happen to be here.
  chk "no description produces two cards" \
    "$(jq '[.[].action]|length - (unique|length)' "$DECK")" 0
  # Since the standalone release, install.sh owns these files and chezmoi does
  # not. Two owners for one file is exactly the drift this suite exists to
  # catch, so tracking them again would be the regression.
  # Anchored on the installed target paths: chezmoi legitimately manages the
  # run_onchange script that calls install.sh, and that name matches too.
  have chezmoi && { chezmoi managed 2>/dev/null | grep -qE '^\.local/(bin/omarchy-keybind-trainer|lib/omarchy/omarchy_theme\.py|share/omarchy-keybind-trainer|share/applications/omarchy-keybind-trainer\.desktop)$' \
    && no "chezmoi is tracking installer-owned files again - two owners, one file" \
    || ok "installer-owned files are not also chezmoi-tracked"; }
  [ -d "$HOME/.local/src/omarchy-keybind-trainer/.git" ] \
    && ok "installed from the release clone" \
    || no "no release clone at ~/.local/src/omarchy-keybind-trainer"
fi

echo
SUFFIX=""; [ "$WARN" -gt 0 ] && SUFFIX=", $WARN warning(s)"
if [ "$FAIL" = 0 ]; then printf '\033[32m%d passed%s\033[0m\n' "$PASS" "$SUFFIX"
else printf '\033[31m%d passed, %d failed%s\033[0m\n' "$PASS" "$FAIL" "$SUFFIX"; fi
exit $((FAIL > 0))
