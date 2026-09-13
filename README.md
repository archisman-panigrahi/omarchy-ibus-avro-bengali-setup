# Setting up IBus Avro (Bengali) on Omarchy/Hyprland

A step-by-step guide to get **Avro Phonetic** (Bengali typing) working reliably in
every app on **Omarchy** (Arch + Hyprland, uwsm-managed session, Lua config).

The recipe follows IBus 1.5.32+ Wayland input-method protocol v2, where candidates
are rendered by the compositor instead of in a separate (focus-stealing) window.

Verified on: Omarchy, ibus 1.5.34, ibus-avro 1.2, Hyprland 0.56.x, uwsm.

## TL;DR

```bash
# 1. Install
sudo pacman -S ibus
yay -S ibus-avro

# 2. Put IM env in the right place (must beat Omarchy's default fcitx env.d)
sudo install -o root -g root -m 0644 -D /dev/stdin /etc/environment.d/99-ibus.conf <<'EOF'
GTK_IM_MODULE=wayland
QT_IM_MODULES=wayland;ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
SDL_IM_MODULE=ibus
GLFW_IM_MODULE=ibus
INPUT_METHOD=ibus
EOF
```

Then add the three Hyprland Lua snippets from [`files/`](files/):
[`autostart-ibus.lua`](files/hypr/autostart-ibus.lua),
[`bindings-ibus.lua`](files/hypr/bindings-ibus.lua),
[`windowrule-ibus.lua`](files/hypr/windowrule-ibus.lua).

Log out and back in. Toggle Bengali with **Super+Shift+Space**.

---

## Why these specific changes?

Three things break ibus on Omarchy out of the box:

1. **Omarchy uses a Lua main config.** `~/.config/hypr/hyprland.lua` is what runs;
   `exec-once`/`env` lines in `hyprland.conf` are ignored. So ibus must be started
   with `o.exec_on_start(...)` in `autostart.lua` — not `exec-once`.

2. **Omarchy sets fcitx as the IM env and it wins.** `/usr/lib/environment.d/10-omarchy-fcitx.conf`
   sets `QT_IM_MODULE/XMODIFIERS/SDL_IM_MODULE/INPUT_METHOD=fcitx`, and on the
   current systemd builds `/usr/lib/environment.d` is applied **after**
   `~/.config/environment.d`, overriding any user values. fcitx5 is not even
   running on a default Omarchy, so those vars point apps at nothing.
   → Put the override in `/etc/environment.d` (applied last → wins).

3. **The wrong panel breaks typing.** `ibus-daemon -drx` starts the old X11-style
   GTK panel, which opens as a real top-level window in Hyprland — it steals focus,
   dies after one character, and typing breaks. Use the v2 panel instead:
   `ibus start --type wayland`.

Also, Omarchy binds **Super+Shift+Space** to "Toggle top bar"
(`default/hypr/bindings/utilities.lua`), and Hyprland fires *every* matching
binding — so the engine toggle must first unbind it.

## Step-by-step

### 1. Install packages

```bash
sudo pacman -S ibus
yay -S ibus-avro
```

### 2. Fix the IM environment (systemd user session)

Set the IM vars so new sessions capture ibus, not fcitx:

```bash
sudo install -o root -g root -m 0644 -D /dev/stdin /etc/environment.d/99-ibus.conf <<'EOF'
# Override Omarchy's default fcitx IM env (/usr/lib/environment.d/10-omarchy-fcitx.conf)
GTK_IM_MODULE=wayland
QT_IM_MODULES=wayland;ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
SDL_IM_MODULE=ibus
GLFW_IM_MODULE=ibus
INPUT_METHOD=ibus
EOF
```

Note: the same file also works in `~/.config/environment.d/10-ibus.conf` on most
setups, but is **not** reliable here (see Reason 2), so `/etc` is the safe spot.
The variables are written to `files/environment.d/99-ibus.conf`.

To verify what the generated session env will be:

```bash
/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator \
  | grep -iE "im_module|xim|input_method|sdl_im"
# expect: every IM var = ibus or wayland, no "fcitx"
```

To also fix the *current* session without relogging:

```bash
systemctl --user set-environment GTK_IM_MODULE=wayland QT_IM_MODULES='wayland;ibus' \
  QT_IM_MODULE=ibus XMODIFIERS='@im=ibus' SDL_IM_MODULE=ibus GLFW_IM_MODULE=ibus INPUT_METHOD=ibus
```

### 3. Start ibus from Hyprland (Lua autostart)

Add the contents of [`files/hypr/autostart-ibus.lua`](files/hypr/autostart-ibus.lua)
to `~/.config/hypr/autostart.lua`:

```lua
-- IBus (ibus-avro). This setup runs the Lua main config; hyprland.conf's
-- exec-once/env are ignored in that mode.
-- Do NOT use `ibus-daemon -drx` (old GTK panel steals focus / breaks typing).
o.exec_on_start("ibus start --type wayland")
```

This fires once per session on the `hyprland.start` event.

### 4. Keybinding to toggle Bengali/English

Super+Space is the Omarchy launcher, so use Super+Shift+Space — but first unbind
Omarchy's "Toggle top bar" on the same combo. Add the contents of
[`files/hypr/bindings-ibus.lua`](files/hypr/bindings-ibus.lua) to
`~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + SPACE")
o.bind("SUPER + SHIFT + SPACE", "IBus Avro toggle",
  "sh -c 'e=$(ibus engine); if [ \"$e\" = ibus-avro ]; then ibus engine xkb:us::eng; else ibus engine ibus-avro; fi'")
```

Verify only your binding remains on that combo:

```bash
hyprctl reload
hyprctl binds -j | grep -A2 '"key":"SPACE"'     # or: python3 -m json.tool
```

### 5. (Optional) Window-rule safety net

Add [`files/hypr/windowrule-ibus.lua`](files/hypr/windowrule-ibus.lua) to
`~/.config/hypr/hyprland.lua` so any ibus window can never steal focus:

```lua
o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })
```

With the v2 panel this is a safety net only (candidates are compositor popups).

### 6. Reload and re-login

```bash
hyprctl reload && hyprctl configerrors   # configerrors → empty
```

**Log out and back in.** Already-running apps keep the session-start env until a
fresh session; the re-login also auto-starts ibus via `autostart.lua`.

## Verify it works

```bash
# ibus stack is running:
ps aux | grep -iE "ibus|avro"

# expected:
#   /usr/lib/ibus/ibus-ui-gtk3 --enable-wayland-im --exec-daemon ...
#   ibus-daemon --xim --panel disable
#   /usr/lib/ibus/ibus-x11 --kill-daemon
#   /usr/lib/ibus/ibus-extension-gtk3      ← SNI tray icon (shows in Omarchy's bar)
#   ibus-daemon ... / gjs .../ibus-avro    ← Avro engine on demand

# Avro exists and toggles:
ibus list-engine | grep -i avro            # ibus-avro - Avro Phonetic
ibus engine ibus-avro && ibus engine
ibus engine xkb:us::eng && ibus engine
```

Then type in a native Wayland GTK app (e.g. Firefox/LibreOffice), a Qt app, and a
terminal. Candidates are compositor popups; the tray icon is in the Omarchy top bar.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Bengali doesn't appear in most apps | ibus not running: relaunch; check `ps aux \| grep -iE "ibus\|avro"`; the env is fcitx-leftover: set `/etc/environment.d/99-ibus.conf` + relogin |
| Super+Shift+Space hides the top bar | Omarchy default has the same combo — keep the `hl.unbind("SUPER + SHIFT + SPACE")` line before your `o.bind` |
| No tray icon | ibus wasn't autostarted (or session started before `autostart.lua` change); Omnarchy bar shows SNI icons, extension-gtk3 provides one |
| Candidate menu steals focus / dies after one char | An old-style daemon got started — remove any `ibus-daemon -drx` autostart, use only `o.exec_on_start("ibus start --type wayland")` |
| Engine switch does nothing | `ibus engine` needs the daemon: after `ibus start --type wayland`, toggle works daemon-side even before relogin |
| Stale fcitx vars in systemd user env | `systemctl --user set-environment ...` (see step 2) fixes the live session; `/etc/environment.d/99-ibus.conf` fixes future sessions |

## Files

- `files/environment.d/99-ibus.conf` — the `/etc/environment.d` override
- `files/hypr/autostart-ibus.lua` — add to `~/.config/hypr/autostart.lua`
- `files/hypr/bindings-ibus.lua` — add to `~/.config/hypr/bindings.lua`
- `files/hypr/windowrule-ibus.lua` — add to `~/.config/hypr/hyprland.lua`

## Gotchas

- Never autostart both the v2 panel and `ibus-daemon -drx` — the two panels race
  and one kills the other mid-typing.
- Do set `GTK_IM_MODULE=wayland` (not `ibus`) on a Wayland session so GTK apps use
  the compositor text-input path.
- `IO_IM_MODULE`... there is no such thing, but everything named
  `QT_IM_MODULES=wayland;ibus` is intentional: Qt first prefers the Wayland
  native path, then falls back to its ibus plugin.