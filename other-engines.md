# Using this setup for other IBus engines / languages

Everything in this repo is really about **fixing IBus itself on Omarchy/Hyprland**:
the environment override, the auto-start, the keybinding and the window rule don't
care which engine you type in. Only a few values change when you want a different
language. Avro is just the example.

## What's engine-specific vs. what isn't

| Piece | Engine-specific? |
|---|---|
| `/etc/environment.d/99-ibus.conf` (7 IM env vars) | No |
| `o.exec_on_start("ibus start --type wayland")` in autostart.lua | No |
| `o.window("(ibus|IBus|...)", { float, no_focus })` in hyprland.lua | No (tweak regex only if needed) |
| AUR package to install | **Yes** |
| Engine ID in `preload-engines` / `engines-order` | **Yes** |
| Engine ID inside the Ctrl+Space toggle command | **Yes** |

## Adapting for a new language — the steps

**1. Install an engine that provides the language.**

A few common ones (all installable via `yay`/`pacman`):

| Language | Package | Engine ID(s) |
|---|---|---|
| Bengali Phonetic | `ibus-avro-git` (or `ibus-avro`) | `ibus-avro` |
| Many Indic langs (incl. Bengali/Marathi/Tamil...) | `ibus-m17n` | `m17n:mr:itrans`, `m17n:bn:inscript`, ... |
| Chinese Pinyin | `ibus-libpinyin` | `libpinyin` |
| Chinese Rime | `ibus-rime` | `rime` |
| Japanese | `ibus-anthy` / `ibus-kkc` | `anthy` |
| Korean | `ibus-hangul` | `hangul` |

**2. Find the engine ID.** Run `ibus list-engine` right after installing. The ID is
the first column — e.g. `ibus-avro - Avro Phonetic` → `ibus-avro`.

**3. Preload the engine** (so it's switchable at all — a fresh install lists it
nowhere by default):

```bash
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', '<engine-id>']"
gsettings set org.freedesktop.ibus.general engines-order "['<engine-id>', 'xkb:us::eng']"
gsettings get org.freedesktop.ibus.general preload-engines   # verify
```

English stays the default; your language is one keypress away.

**4. Point the toggle at that engine.** Edit the `o.bind("CTRL + SPACE", ...)`
line in `bindings.lua` and swap `ibus-avro` for your engine ID:

```lua
o.bind("CTRL + SPACE", "IBus <lang> toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = <engine-id> ]; then ibus engine xkb:us::eng; else ibus engine <engine-id>; fi'")
```

If you'd rather not hand-write the toggle: leave the keybinding out entirely and
use IBus's **built-in trigger** (default `Control+space`, same combo) — IBus then
cycles through every engine in `preload-engines`.

**5. Adjust the window rule only if needed.** The regex
`(ibus|IBus|Avro|avro|org\.freedesktop\.IBus)` is deliberately loose and covers
generic IBus windows. If your engine spawns windows with a different class, just
append it to that pattern in `hyprland.lua`.

**6. Restart.** Because apps capture the IM env at login, log out and back in
(a plain `pkill`+`ibus start --type wayland` works for a quick test, but the tray
icon and full app coverage need the reload).

## Worked example: Marathi via `ibus-m17n`

```bash
yay -S --needed ibus-m17n
ibus list-engine | grep m17n:mr        # -> m17n:mr:itrans
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'm17n:mr:itrans']"
gsettings set org.freedesktop.ibus.general engines-order "['m17n:mr:itrans', 'xkb:us::eng']"
```

Then swap `ibus-avro` → `m17n:mr:itrans` in the `bindings.lua` toggle.

## Caveats

- `ibus-avro` is a gjs-based engine shipped straight from AUR; other engines vary in
  maturity and defaults. Engines like Rime or libpinyin may need their own
  configuration (e.g. dictionaries) *after* IBus starts — check the engine's docs.
- The `-drx` panel problem, fcitx env override and focus-stealing all apply to any
  engine — that's why these generic parts are the bulk of the repo.
- One engine ID per toggle: if you want to cycle through many languages, prefer
  IBus's built-in `Control+space` (with all IDs in `preload-engines`) over a long
  shell one-liner.