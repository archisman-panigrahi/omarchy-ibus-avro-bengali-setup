# How `setup-ibus-avro.sh` works

## Why the problem exists

On Omarchy/Hyprland, Bengali typed via IBus Avro is broken out of the box for four compounding reasons:

1. **`hyprland.conf` is ignored.** The session boots from a Lua main config
   (`~/.config/hypr/hyprland.lua`). Omarchy's starter config relies on
   `exec-once`/`env` in `hyprland.conf`, which never run in Lua mode — so IBus
   never auto-starts and any env in that file never applies.
2. **The wrong input-method env wins.** Omarchy ships
   `/usr/lib/environment.d/10-omarchy-fcitx.conf` with
   `QT_IM_MODULE/XMODIFIERS/SDL_IM_MODULE/INPUT_METHOD=fcitx`. Apps pick up their
   input-method module from the session env, and `fcitx5` isn't even running — so
   most apps get **no** input method at all. A user override in
   `~/.config/environment.d` is *not* enough here.
3. **The default daemon mode is wrong for Wayland.** Omarchy's `autostart.lua`
   runs `ibus-daemon -drx`, which opens the old X11 GTK candidate panel as a real
   window. On Wayland it steals focus, arr corner the typing, and shows no proper
   tray/SNI icon.
4. **The default engine is English.** A fresh `ibus-avro` install isn't listed in
   IBus's `preload-engines`, so Avro isn't even switchable.

Plus two conventions that shape the fix:

- The toggle key is **Ctrl+Space**: Omarchy has no default binding on it (its space
  bindings take a `SUPER` modifier), and it matches IBus's own default trigger
  (`Control+space`), so no `unbind` is needed.
- Re-running setup must be safe: files get backed up, and modified blocks must be
  *replaced*, not appended forever (the previous failure mode).

## What the script does

Numbered steps, bottom-up so that a re-run is idempotent:

### 0. Preflight
Verifies `yay` exists (AUR helper) and warns if `hyprctl` is missing (this targets
Omarchy/Hyprland).

### 1. Packages
- `sudo pacman -S --needed --noconfirm ibus` (official repo).
- **Skip-if-installed:** if `pacman -Qq` already lists `ibus-avro` or
  `ibus-avro-git`, the AUR build is skipped. Note: even when the `-git` AUR
  package is used, the engine is registered as `ibus-avro` — so the check covers
  both package names.

### 2. IBus engine config
Fresh installs don't list Avro as a usable engine. The script sets it via
gsettings (the same backend IBus reads — the machines's system dconf DB defaults
both to `[]`):

```bash
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'ibus-avro']"
gsettings set org.freedesktop.ibus.general engines-order "['ibus-avro', 'xkb:us::eng']"
```

English stays the default engine; Ctrl+Space toggles to Bengali. This is the
"post-install IBus config" that would otherwise be manual.

### 3. IM environment
Writes the 7-variable override to **`/etc/environment.d/99-ibus.conf`** (as root,
via `install -D`, so the directory is created if needed). This is the one place
that outranks Omarchy's `/usr/lib/environment.d/10-omarchy-fcitx.conf`, because
systemd applies `/usr/lib`, then `/usr/local/lib`, then `/etc`, then user dirs —
with later wins. So `/etc` wins over the fcitx defaults and over any user override.

Variables written:

```
GTK_IM_MODULE=wayland
QT_IM_MODULES=wayland;ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
SDL_IM_MODULE=ibus
GLFW_IM_MODULE=ibus
INPUT_METHOD=ibus
```

If `/etc` needs sudo and that fails, it falls back to
`~/.config/environment.d/10-ibus.conf` and warns that it may still lose to the
fcitx file on some systemd builds.

It also applies the same variables to the live systemd user manager
(`systemctl --user set-environment`), so already-running Qt/GTK apps can pick
them up without waiting for reboot, and prints what
`30-systemd-environment-d-generator` would hand the next session ("expect no
fcitx").

### 4. Hyprland Lua patches
All three files live in `$HYPR_CFG` (`~/.config/hypr`).

The script uses **marker blocks** (`---[BEGIN]|omarchy-ibus-avro` /
`---[END]|omarchy-ibus-avro`; bindings uses `>>> ... <<<`) and an **upsert**
helper: if the marker is already in the file, the whole block is replaced
(awk skips between markers, then the new block is appended); if not, it's
appended; if the file doesn't exist, it's created. Each modified file is backed
up to `<file>.bak.<timestamp>` first. This is what makes re-runs safe.

- **autostart.lua** — first *removes* any legacy
  `o.exec_on_start("ibus-daemon ...")` line (the restored Omarchy default would
  otherwise race with our line), then adds
  `o.exec_on_start("ibus start --type wayland")`.
  `o.exec_on_start` is required because `exec-once` in `hyprland.conf` is dead in
  Lua mode. `--type wayland` uses the input-method protocol v2 panel: candidates
  render as compositor popups, so no focus-stealing window, and the tray/SNI icon
  comes from `ibus-extension-gtk3`.
- **bindings.lua** — adds
  `o.bind("CTRL + SPACE", "IBus Avro toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = ibus-avro ]; then ibus engine xkb:us::eng; else ibus engine ibus-avro; fi'")`.
  Ctrl+Space is chosen because Omarchy has no default on it (its Space bindings
  take a `SUPER` modifier), so no `hl.unbind` is needed.
- **hyprland.lua** — adds a focus-safety rule so IBus/Avro windows never tile or
  steal focus:
  `o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })`
  (a safety net for XWayland/XIM fallbacks; the v2 panel is already compositor
  popups).

### 5. Reload
If `hyprctl` is available and `HYPRLAND_INSTANCE_SIGNATURE` is set (i.e. we're in
a live Hyprland session), it runs `hyprctl reload` and `hyprctl configerrors` to
sanity-check the patched Lua.

### 6. Wrap up + logout
Prints a summary, then asks "Log out now?" Read from stdin with a guard so a
closed pipe can't abort the script under `set -e`.

On "yes" it logs out via **`uwsm stop`** — the same command Omarchy's own Logout
menu item runs (the earlier `hyprctl exit` was invalid on this build and printed
`unknown request`). If `uwsm` isn't present it falls back to
`hyprctl dispatch exit`.

## Why the log-out login matters

The session env used by the desktop (and your *launcher*) is captured at login —
rewriting `/etc/environment.d` doesn't retroactively change running apps. Only
after a fresh log-in does the session get captured with `ibus`, so IBus
auto-starts and the tray icon appears.

## Summary of the fix vs the symptoms

| Symptom | Fix |
|---|---|
| No IBus after login | `o.exec_on_start("ibus start --type wayland")` |
| Apps get fcitx mode / no IM module | `/etc/environment.d/99-ibus.conf` override |
| Focus-stealing candidate window | `--type wayland` (v2 panel) |
| Avro not switchable | gsettings `preload-engines` / `engines-order` |
| Toggle combo collides with Omarchy | **Ctrl+Space** (no Omarchy default) |
| Re-runs duplicate edits / no rollback | marker-block upsert + `.bak.<timestamp>` backend-up |
| Script aborts on closed stdin / invalid logout | guarded `read`, `uwsm stop` |