#!/usr/bin/env bash
# Install omarchy-keybind-trainer into your home directory.
# Idempotent: safe to re-run to upgrade. Nothing is installed system-wide,
# nothing needs root, and no file outside $HOME is touched.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-keybind-trainer"
LIB_DIR="$HOME/.local/lib/omarchy"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
ROW_ID="learn.keybind-drill"

say(){ printf '  %s\n' "$1"; }
die(){ printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

echo "Installing omarchy-keybind-trainer"

# --- refuse to half-install -------------------------------------------------
command -v python3 >/dev/null || die "python3 is required."
command -v hyprctl >/dev/null || die "hyprctl not found. This drill reads your live Hyprland keybindings and cannot do anything without it."
for f in omarchy-keybind-trainer app.html omarchy_theme.py omarchy-keybind-trainer.desktop; do
  [ -f "$SRC/$f" ] || die "missing $f - is this a complete checkout?"
done
if [ ! -d /usr/share/omarchy ]; then
  say "warning: /usr/share/omarchy not found. The drill needs Omarchy's"
  say "         o.bind(...) keybindings — a plain Hyprland config has no"
  say "         descriptions to drill. Installing anyway."
fi

# --- files ------------------------------------------------------------------
install -Dm755 "$SRC/omarchy-keybind-trainer" "$BIN_DIR/omarchy-keybind-trainer"
install -Dm644 "$SRC/app.html"                "$DATA_DIR/app.html"
install -Dm644 "$SRC/omarchy-keybind-trainer.desktop" "$APPS_DIR/omarchy-keybind-trainer.desktop"
say "installed $BIN_DIR/omarchy-keybind-trainer"
say "installed $DATA_DIR/app.html"
say "installed $APPS_DIR/omarchy-keybind-trainer.desktop"

# The theme resolver is shared with omarchy-catalog, so it goes to the shared
# path both tools look in rather than somewhere private to this one.
if [ -f "$LIB_DIR/omarchy_theme.py" ] && ! cmp -s "$SRC/omarchy_theme.py" "$LIB_DIR/omarchy_theme.py"; then
  cp -a "$LIB_DIR/omarchy_theme.py" "$LIB_DIR/omarchy_theme.py.bak"
  say "backed up your existing omarchy_theme.py to omarchy_theme.py.bak"
fi
install -Dm644 "$SRC/omarchy_theme.py" "$LIB_DIR/omarchy_theme.py"
say "installed $LIB_DIR/omarchy_theme.py (shared with omarchy-catalog)"

command -v update-desktop-database >/dev/null \
  && update-desktop-database "$APPS_DIR" 2>/dev/null || true

# --- the Omarchy menu row ---------------------------------------------------
# Omarchy merges ~/.config/omarchy/extensions/omarchy-menu.jsonc over its
# defaults, by id, user-wins-per-key. There is exactly one such file and no
# drop-in directory, so this has to edit a file that is probably yours already.
#
# It is edited as TEXT, never round-tripped through a JSON parser: a
# round-trip would silently delete every comment and all your formatting. And
# it is validated before being left in place, because Omarchy's loader answers
# a parse error by dropping *every* user menu row, with the only complaint
# going to the shell log.
MENU_RESULT=$(python3 - "$MENU" "$ROW_ID" <<'PY'
import json, re, shutil, sys
from pathlib import Path

menu, row_id = Path(sys.argv[1]), sys.argv[2]
ROW = ('  "%s": {"icon":"\\udb80\\udf0c","label":"Keybinding drill",'
       '"description":"Practise your own keybindings by pressing them",'
       '"aliases":["drill","practice","quiz"],'
       '"action":"omarchy-keybind-trainer"}' % row_id)


def parses(text):
    """Omarchy's own stripJsonc: whole-line // comments, trailing commas."""
    stripped = re.sub(r"^\s*//[^\n]*(\n|$)", "", text, flags=re.M)
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    try:
        return isinstance(json.loads(stripped), dict)
    except ValueError:
        return False


if menu.is_file():
    original = menu.read_text()
    if f'"{row_id}"' in original:
        print("SKIP"); raise SystemExit(0)
    if not parses(original):
        print("UNPARSEABLE"); raise SystemExit(0)
    close = original.rfind("}")
    if close < 0:
        print("UNPARSEABLE"); raise SystemExit(0)
    head, tail = original[:close], original[close:]
    # Keep the file's own trailing whitespace so uninstall can put it back
    # byte for byte.
    body = head.rstrip()
    gap = head[len(body):] or "\n"
    if not body.endswith("{") and not body.endswith(","):
        body += ","
    updated = f"{body}\n{ROW}{gap}{tail}"
else:
    original = None
    updated = "{\n" + ROW + "\n}\n"

if not parses(updated):
    print("WOULD_BREAK"); raise SystemExit(0)

if original is not None:
    shutil.copy2(menu, menu.with_suffix(menu.suffix + ".bak"))
menu.parent.mkdir(parents=True, exist_ok=True)
menu.write_text(updated)
print("ADDED")
PY
)
case "$MENU_RESULT" in
  ADDED)       say "added the menu row: Omarchy menu -> Learn -> Keybinding drill" ;;
  SKIP)        say "menu row already present" ;;
  UNPARSEABLE) say "warning: $MENU does not parse as JSONC - left it untouched." ;;
  WOULD_BREAK) say "warning: adding the menu row would have broken $MENU - left it untouched." ;;
  *)           say "warning: could not edit $MENU - left it untouched." ;;
esac
case "$MENU_RESULT" in
  ADDED|SKIP) ;;
  *) say "         Launch from your app launcher instead." ;;
esac

echo
echo "Done. Launch it from:"
echo "  • Omarchy menu -> Learn -> Keybinding drill"
echo "  • your app launcher (\"Keybinding Drill\")"
echo "  • the command line: omarchy-keybind-trainer"
echo
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not on your PATH." ;;
esac
echo "If a binding is ever left suspended: omarchy-keybind-trainer --restore"
