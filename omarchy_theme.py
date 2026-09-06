"""Resolve the active Omarchy theme into a UI palette.

Shared by the browser-based Omarchy tools (`omarchy-keybind-trainer`,
`omarchy-catalog`) so the contrast handling below lives in exactly one place.
Import it with:

    sys.path.insert(0, str(Path.home() / ".local/lib/omarchy"))
    from omarchy_theme import theme_colors

See ~/Projects/Omarchy_config/catalog/README.md.
"""

import re
from pathlib import Path

THEME_DIR = Path.home() / ".local/state/omarchy/current/theme"


def theme_source(theme_dir=None):
    """The file `theme_colors` would actually read, or None.

    A theme directory with neither file resolves to the built-in defaults, and
    the result looks like a perfectly plausible palette - so a broken or empty
    theme passes every contrast check while wearing somebody else's colours.
    Callers that need to tell the difference ask here.
    """
    root = Path(theme_dir) if theme_dir else THEME_DIR
    for name in ("colors.toml", "alacritty.toml"):
        if _parse_toml_colors(root / name):
            return root / name
    return None


def _hex(c):
    """Accepts #rrggbb, #rgb and 0xrrggbb; raises on anything else.

    Third-party themes are arbitrary text. A short form used to reach
    int("", 16) and take down the whole page along with the heartbeat.
    """
    c = str(c).strip().lstrip("#")
    if c[:2].lower() == "0x":
        c = c[2:]
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    if len(c) < 6 or any(ch not in "0123456789abcdefABCDEF" for ch in c[:6]):
        raise ValueError(f"not a hex colour: {c!r}")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _rgb(v):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x))) for x in v)


def mix(a, b, t):
    """Blend two hex colours. t=0 -> a, t=1 -> b."""
    x, y = _hex(a), _hex(b)
    return _rgb([x[i] + (y[i] - x[i]) * t for i in range(3)])


def luminance(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in _hex(c))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _parse_toml_colors(path):
    out = {}
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return out
    for line in text.splitlines():
        m = re.match(r'\s*([A-Za-z_0-9]+)\s*=\s*"([^"]+)"', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def _hue(c):
    r, g, b = (v / 255 for v in _hex(c))
    hi, lo = max(r, g, b), min(r, g, b)
    if hi == lo:
        return None                      # greyscale: no meaningful hue
    d = hi - lo
    if hi == r:
        h = ((g - b) / d) % 6
    elif hi == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h * 60


def _semantic(colour, lo, hi, fallback, bg, dark):
    """Keep a theme colour only if its hue actually reads as that meaning.

    Some themes have no green or yellow at all - moodpeak's ANSI "green" is
    teal and its "yellow" is cyan, which would make correct, warning and wrong
    indistinguishable. Fidelity is not worth losing the signal, so a colour
    outside its plausible hue band is replaced by a neutral one nudged toward
    the theme's own background.
    """
    h = _hue(colour)
    inside = h is not None and (lo <= h <= hi if lo <= hi else (h >= lo or h <= hi))
    if inside:
        return colour
    return mix(fallback, bg, 0.12 if dark else 0.0)


def _readable_on(base, *candidates, target=4.5):
    """Text colour for a filled block, falling back to black/white."""
    best = max(candidates, key=lambda c: contrast(c, base))
    if contrast(best, base) >= target:
        return best
    return max(("#000000", "#ffffff"), key=lambda c: contrast(c, base))


def _step_until(a, b, start, floor, target):
    """Mix `a` toward `b`, backing off until it clears a contrast floor."""
    t = start
    while t > floor and contrast(mix(a, b, t), b) < target:
        t -= 0.04
    return mix(a, b, t)


def _deepen_against(colour, surface, toward, target=3.0):
    """Push a colour toward `toward` until it reads on `surface`, keeping hue."""
    t = 0.0
    while t <= 0.9 and contrast(mix(colour, toward, t), surface) < target:
        t += 0.05
    return mix(colour, toward, t)


def theme_colors():
    """Resolve the active Omarchy theme into the drill's palette.

    `colors.toml` ships in two shapes. Most themes use semantic keys (`mode`,
    `selection`, `muted`, `red`/`green`/`yellow`); a few - cobalt2, black_arch,
    moodpeak - use terminal keys (`color0..15`) with no `mode`, and neovoid
    ships none at all. Only `accent`, `foreground` and `background` are present
    everywhere, so every surface tone is derived from those rather than read,
    and `mode` falls back to background luminance.
    """
    raw = _parse_toml_colors(THEME_DIR / "colors.toml")
    if not raw:
        raw = _parse_toml_colors(THEME_DIR / "alacritty.toml")

    bg = raw.get("background", "#1a1b26")
    fg = raw.get("foreground", "#c0caf5")
    accent = raw.get("accent") or raw.get("color4", "#7aa2f7")
    ok = raw.get("green") or raw.get("color2", "#9ece6a")
    bad = raw.get("red") or raw.get("color1", "#f7768e")
    warn = raw.get("yellow") or raw.get("color3", "#e0af68")

    dark = (raw.get("mode") or ("light" if luminance(bg) > 0.4 else "dark")) == "dark"

    # Correct / warning / wrong must stay tellable apart even on a palette that
    # has no green or amber in it.
    ok = _semantic(ok, 65, 170, "#6fbf73" if dark else "#2f8f4e", bg, dark)
    warn = _semantic(warn, 18, 60, "#e0a83c" if dark else "#a86a06", bg, dark)
    bad = _semantic(bad, 330, 20, "#ef7285" if dark else "#c0304a", bg, dark)

    # A theme's own amber can be too pale to read on a near-white card
    # (catppuccin-latte, flexoki-light, rose-pine). Deepen the hue rather than
    # swap it: mix toward the foreground until it clears 3:1 on the surface.
    deepen = lambda c: _deepen_against(c, bg, fg)
    ok, warn, bad = deepen(ok), deepen(warn), deepen(bad)

    card = bg
    page = mix(bg, "#000000", 0.30 if dark else 0.05)
    # Fixed mixes drop under 3:1 on the low-contrast light themes (rose-pine,
    # catppuccin-latte), so these back off until they clear.
    muted = _step_until(fg, bg, 0.42, 0.10, 4.0)
    faint = _step_until(fg, bg, 0.66, 0.30, 2.6)
    black_or_white = lambda c: max(("#000000", "#ffffff"), key=lambda x: contrast(x, c))

    return {
        "page": page,
        "card": card,
        "sunk": mix(card, fg, 0.06),
        "track": mix(card, fg, 0.12),
        "fg": fg,
        "muted": muted,
        "faint": faint,
        "accent": accent,
        "on-accent": _readable_on(accent, bg, fg),
        "ok": ok, "on-ok": black_or_white(ok), "ok-bg": mix(card, ok, 0.16),
        "bad": bad, "on-bad": black_or_white(bad), "bad-bg": mix(card, bad, 0.16),
        "warn": warn, "on-warn": black_or_white(warn),
        "warn-bg": mix(card, warn, 0.18),
        "warn-ink": mix(warn, fg, 0.25),
        "key": mix(bg, fg, 0.14),
        "key-hi": mix(bg, fg, 0.22),
        "key-skirt": mix(card, "#000000", 0.55 if dark else 0.22),
        "key-shadow": "rgba(0,0,0,%.2f)" % (0.45 if dark else 0.18),
        "e1": "0 1px 2px rgba(0,0,0,%.2f), 0 8px 22px rgba(0,0,0,%.2f)"
              % ((0.30, 0.34) if dark else (0.05, 0.07)),
        "e2": "0 2px 4px rgba(0,0,0,%.2f), 0 18px 40px rgba(0,0,0,%.2f)"
              % ((0.34, 0.42) if dark else (0.06, 0.10)),
    }


