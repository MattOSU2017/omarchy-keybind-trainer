# omarchy-keybind-trainer

A drill game for your Omarchy keybindings that makes you **press the real
keys**.

Hyprland grabs `SUPER + <key>` at the compositor, so a browser can never see
it — which is why every other shortcut trainer is multiple choice. This one
**temporarily unbinds whichever binding it is testing**, so the keystroke falls
through to the page instead of firing the action. Nothing launches, nothing
closes, nothing switches. Then it binds it straight back.

That turns it from a quiz into muscle memory.

It reads your live binding set from `hyprctl binds` on every page load, so it
drills *your* config — including everything you have added yourself — and it
takes its colours from your active Omarchy theme.

## Install

```bash
git clone https://github.com/MattOSU2017/omarchy-keybind-trainer
cd omarchy-keybind-trainer && ./install.sh
```

No root, no dependencies beyond Python 3 (stdlib only) and Omarchy itself.
Everything lands under `$HOME`; nothing system-wide is touched.

Then launch it from **Omarchy menu → Learn → Keybinding drill**, from your app
launcher ("Keybinding Drill"), or by running `omarchy-keybind-trainer`.

To upgrade: `git pull && ./install.sh`. To remove: `./uninstall.sh`
(add `--keep-progress` to keep your stats).

## Three modes

| Mode | What it does |
|---|---|
| **Live fire** | Shows an action, you press the real binding. The drill holds that binding down while it asks. |
| **Keys → action** | Shows a combo, you pick what it does. Never touches your config. |
| **Quiet quiz** | Multiple choice, both directions. Never touches your config. |

Bindings you keep missing come back around three times as often within a
session, and your stats persist in
`~/.local/state/omarchy/keybind-trainer/progress.json` — plain JSON you can
read, grep or delete.

## It teaches the pattern, not 200 unrelated facts

Keybindings feel arbitrary one at a time. Mostly they aren't — the letter
usually stands for the action and the modifiers usually sort bindings into
groups — but nothing ever tells you that, so drilling them feels like rote
memorisation.

So the drill reads the pattern **out of your own config** and shows it. On the
start screen you get your keyboard's grammar:

```
SUPER + CTRL          a system setting or toggle        76% of 21
SUPER + SHIFT         launch an app                    100% of 17
SUPER                 usually manage the window …       67% of 13
SUPER + ALT + SHIFT   launch an app                    100% of 7
```

and after every answer, one line saying why that key:

> `SUPER + ALT + SHIFT` = launch an app · **B** for **Browser** · the other `B` — `SUPER + SHIFT + B` is Browser

Nothing here is a table of anyone's keybindings. Three signals, all derived:

- **letter** — the key starts a word in the action ("G for Gallery")
- **family** — that modifier set's bindings mostly share a category, so it has
  a consistent meaning on *your* machine
- **variant** — the same key with fewer modifiers holds a related binding, and
  the two actions actually name the same thing. "Browser" and "Browser
  (private)" qualify; "Photo Gallery" and "Toggle window grouping" don't, so
  that link is not offered.

A config organised differently produces different rules. A config with no
system produces none and says so — and rules are hedged by how well they hold,
so a 67% pattern is reported as "usually", never as fact. Only letter keys vote
on a modifier's meaning, because "which modifier was it?" is a question about
`SUPER+SHIFT+E`, never about an arrow key.

**Then it tells you the ones that really are arbitrary.** A binding whose key
has no letter link and no variant link gets flagged, and the start screen
offers to drill just those. On the author's 193-card deck that is **20 cards** —
the ones worth inventing a hook for, instead of treating all 193 as random.

It doubles as a config review: a binding that breaks your own pattern is
sometimes better rebound than memorised.

## Your keyboard is never left broken

This is the part that has to be right, because the failure mode is *"my
keybindings stopped working and I don't know why"*. Five independent layers:

1. **Verify, never assume.** A binding is only asked for if re-reading
   `hyprctl binds` confirms it is actually down. Anything that will not
   suspend silently becomes multiple choice instead.
2. **Re-checked every five seconds.** Hyprland restores every binding whenever
   *any* config file is saved — an editor, a theme switch, another tool. The
   drill re-reads the compositor on each heartbeat, and if a binding came back
   underneath a question it stops asking you to press it.
3. **Restored on every exit** — normal close, `SIGTERM`, and a 90-second
   watchdog if the page stops talking.
4. **A dead-man switch.** A transient `systemd` timer runs `hyprctl reload`
   even if the process is killed with `-9`. It checks whether the drill is
   still alive before firing, so a long session is never interrupted.
5. **A marker file**, healed on next launch, in case even that does not run.

And the manual escape hatch, which works with nothing else installed:

```bash
omarchy-keybind-trainer --restore
```

Locking, power, log-out and "close all windows" are never live-fired at all —
matched on the description, so it holds whatever *you* have them bound to.

## Known limits

- **Omarchy, not plain Hyprland.** The deck is built from the descriptions in
  Omarchy's `o.bind(...)` bindings. A bare `bind = SUPER,Q,killactive` config
  has nothing to name, and the drill will tell you so rather than show an
  empty deck.
- **Chromium gets the most out of it.** Keyboard Lock lets the page receive
  `Ctrl+W`, `Ctrl+T` and friends. Other browsers work, but keep those
  shortcuts for themselves; the drill says so on screen and `Escape` skips.
- **US-ish keymaps.** Keys outside the built-in keycode map fall back to
  multiple choice rather than live fire.
- **Media keys and mouse bindings** cannot be pressed as key events, so they
  are multiple choice too (~30 cards here).
- **Submaps are skipped.** No spaced repetition, and progress does not sync
  between machines.
- **`hl.unbind` through `hyprctl eval` is not a documented API.** It is the
  only runtime path that works on Omarchy — `hyprctl keyword` is refused by
  its Lua parser — but it could break on an Omarchy update. That is the single
  biggest risk to this tool. If it ever stops suspending, every card falls
  back to multiple choice rather than misfiring.

## Options

```
omarchy-keybind-trainer               launch (detaches, returns immediately)
  --restore                           put every binding back, right now
  --print-deck                        dump the deck as JSON
  --stats                             your weakest bindings
  --reset                             erase saved progress
  --foreground                        do not detach (debugging)
  --port N                            serve on N instead of 8477
```

`$OMARCHY_KEYBIND_TRAINER_PORT` also works. If the port is taken by something
that is not this drill, it picks the next free one rather than pointing your
browser at a stranger.

## What gets installed

| Path | What |
|---|---|
| `~/.local/bin/omarchy-keybind-trainer` | deck builder, suspend manager, HTTP server |
| `~/.local/share/omarchy-keybind-trainer/app.html` | the whole UI, one file |
| `~/.local/lib/omarchy/omarchy_theme.py` | theme resolver (shared with `omarchy-catalog`, if you have it) |
| `~/.local/share/applications/omarchy-keybind-trainer.desktop` | launcher entry |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | one added row, `learn.keybind-drill` |
| `~/.local/state/omarchy/keybind-trainer/` | your progress |

The menu file is the only one you probably already own. It is edited as text,
never round-tripped through a JSON parser (which would delete your comments),
backed up first, and validated before being left in place — Omarchy answers a
malformed extensions file by silently dropping *every* user menu row.

**`~/.config/hypr/` is never written to.**

## Tests

```bash
./selftest.sh
```

Runs on any Omarchy machine. It creates its own scratch binding for the
suspend/restore round-trip, so none of yours is ever touched. Covers deck
invariants, category attribution, the same-origin guard, the heartbeat
detecting a binding restored underneath it, every installed theme's contrast
floors, and each crash-recovery layer.

## Support, honestly

A hobby project, shared because it might save someone else the same trouble.
Issues and Discussions are open and I read them, but I may be slow and I make
no promises — please don't wait on me. It's MIT: fork it, change it, ship your
own version.

Bug reports are genuinely welcome, particularly anything about a binding not
being restored. There are five layers meant to stop that, and if you ever find
one that gets past all of them I want to know.

## Licence

MIT.
