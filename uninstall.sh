#!/usr/bin/env bash
# Remove omarchy-keybind-trainer. Leaves your keybindings exactly as it found
# them and never touches a file it did not install.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-keybind-trainer"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/keybind-trainer"
LIB_DIR="$HOME/.local/lib/omarchy"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
ROW_ID="learn.keybind-drill"
KEEP_STATE=0
[ "${1:-}" = "--keep-progress" ] && KEEP_STATE=1

say(){ printf '  %s\n' "$1"; }
echo "Removing omarchy-keybind-trainer"

# Put any suspended binding back before the tool that knows how to is gone.
if [ -x "$BIN_DIR/omarchy-keybind-trainer" ]; then
  "$BIN_DIR/omarchy-keybind-trainer" --restore >/dev/null 2>&1 \
    && say "bindings restored" || true
fi

rm -f  "$BIN_DIR/omarchy-keybind-trainer" && say "removed the launcher"
rm -rf "$DATA_DIR"                        && say "removed $DATA_DIR"
rm -f  "$APPS_DIR/omarchy-keybind-trainer.desktop" && say "removed the .desktop entry"
command -v update-desktop-database >/dev/null \
  && update-desktop-database "$APPS_DIR" 2>/dev/null || true

if [ "$KEEP_STATE" = 1 ]; then
  say "kept your progress in $STATE_DIR"
else
  rm -rf "$STATE_DIR" && say "removed saved progress ($STATE_DIR)"
fi

# omarchy_theme.py is deliberately left: omarchy-catalog imports the same file,
# and removing it would break a tool this one did not install.
if [ -f "$LIB_DIR/omarchy_theme.py" ]; then
  say "left $LIB_DIR/omarchy_theme.py (omarchy-catalog may share it)"
fi

# Remove our menu row by id, leaving every other row, comment and blank line
# exactly as it was. Validated before being written, for the same reason the
# installer validates: a parse error silently drops all your menu rows.
if [ -f "$MENU" ]; then
  python3 - "$MENU" "$ROW_ID" <<'PY'
import json, re, shutil, sys
from pathlib import Path
menu, row_id = Path(sys.argv[1]), sys.argv[2]
text = menu.read_text()
if f'"{row_id}"' not in text:
    print("  no menu row to remove"); raise SystemExit(0)
kept = [l for l in text.splitlines(keepends=True) if f'"{row_id}"' not in l]
updated = "".join(kept)
# The installer appends a comma to the previous entry to make room. Removing
# our line leaves it dangling: harmless (Omarchy tolerates trailing commas)
# but it means uninstall would not put the file back as it found it.
close = updated.rfind("}")
if close >= 0:
    head, tail = updated[:close], updated[close:]
    body = head.rstrip()
    if body.endswith(","):
        gap = head[len(body):]
        updated = body[:-1] + gap + tail

def parses(t):
    t = re.sub(r"^\s*//[^\n]*(\n|$)", "", t, flags=re.M)
    t = re.sub(r",(\s*[}\]])", r"\1", t)
    try:
        return isinstance(json.loads(t), dict)
    except ValueError:
        return False

if not parses(updated):
    print("  could not remove the menu row safely - left it in place")
    raise SystemExit(0)
shutil.copy2(menu, menu.with_suffix(menu.suffix + ".bak"))
menu.write_text(updated)
print("  removed the menu row")
PY
fi

echo
echo "Done. Your Hyprland config was never written to, so nothing else changed."
