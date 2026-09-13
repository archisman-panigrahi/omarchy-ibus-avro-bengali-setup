# IBus Avro (Bengali) on Omarchy

Fixes Bengali typing on Omarchy/Hyprland. Avro candidates appear as compositor
popups, work in every app, and never steal focus.

## The problem

- Omarchy's Lua config means `hyprland.conf`'s `exec-once`/`env` are ignored —
  IBus never autostarts.
- Omarchy sets `QT_IM_MODULE/XMODIFIERS/SDL_IM_MODULE/INPUT_METHOD=fcitx` in
  `/usr/lib/environment.d/10-omarchy-fcitx.conf`, which overrides user config —
  fcitx5 isn't even running, so most apps get no input method at all.
- The old `ibus-daemon -drx` GTK panel opens as a real window that steals focus
  and kills typing after one character.
- Super+Shift+Space is already Omarchy's "Toggle top bar".

## Fix — run the script

```bash
bash setup-ibus-avro.sh
```

Installs `ibus` + `ibus-avro-git` (AUR via yay), preloads the Avro engine,
writes `/etc/environment.d/99-ibus.conf` (to outrank the fcitx file), patches
`autostart.lua`, `bindings.lua`, `hyprland.lua`, and asks you to log out/in.
Idempotent — safe to re-run.

## After reboot

After you log back in:

- IBus auto-starts (`ibus start --type wayland`), tray icon appears in the top bar.
- **Super+Shift+Space** toggles Bengali (`ibus-avro`) / English (`xkb:us::eng`).
- Verify: `ibus engine` and `ps aux | grep -iE "ibus|avro"`.

Tokens `---[BEGIN]|omarchy-ibus-avro` … `---[END]|omarchy-ibus-avro` in the Lua
files mark the script's changes (backups are `.bak.<timestamp>`).

### Post-install IBus config

Fresh installs don't list Avro as an engine until it's preloaded. The script does
this; to do it manually (e.g. after a reinstall):

```bash
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'ibus-avro']"
gsettings set org.freedesktop.ibus.general engines-order "['ibus-avro', 'xkb:us::eng']"
gsettings get org.freedesktop.ibus.general preload-engines   # verify
```

English stays the default engine; Avro is one Super+Shift+Space away.

## Files

- `setup-ibus-avro.sh` — the installer above
- `files/environment.d/99-ibus.conf` — env override for `/etc/environment.d`
- `files/hypr/*.lua` — the three patched snippets (autostart, binding, window rule)