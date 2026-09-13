# Using this setup for other IBus engines / languages

0. **Run the engine-agnostic base first** (installs `ibus`, writes the IM env
   override, auto-starts ibus in Wayland mode, adds the focus window rule):

   ```bash
   bash base-setup.sh
   ```

   It contains no language/engine name to change — nothing to edit before
   running. (The only Avro-ish bits are the internal block-marker tag, which must
   stay, and the window-rule regex, which already covers generic IBus windows. If
   you know your engine's own window class, you can *optionally* append it to
   that regex in `base-setup.sh` before running — otherwise do it later in
   `hyprland.lua`, see the note below.)

   After the base, only the engine package and its ID change:

1. **Install an engine** (deps pull `ibus` in, but it's already there):
   ```bash
   yay -S --needed ibus-m17n        # Marathi, Tamil, Bengali (inscript), ...
   # others: ibus-libpinyin (zh), ibus-rime (zh), ibus-anthy (ja), ibus-hangul (ko)
   ```
2. **Find its engine ID**:
   ```bash
   ibus list-engine | grep m17n:mr   # example -> m17n:mr:itrans
   ```
   Common IDs: `m17n:mr:itrans`, `m17n:bn:inscript`, `libpinyin`, `rime`,
   `anthy`, `hangul`.
3. **Preload it** (a fresh install doesn't list it as switchable), keeping
   English the default:
   ```bash
   gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', '<engine-id>']"
   gsettings set org.freedesktop.ibus.general engines-order "['<engine-id>', 'xkb:us::eng']"
   ```
4. **Add the toggle** in `bindings.lua`. `base-setup.sh` skips this on purpose
   (it's engine-specific) — copy the block from `files/hypr/bindings-ibus.lua`
   and swap in your ID:
   ```lua
   o.bind("CTRL + SPACE", "IBus <lang> toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = <engine-id> ]; then ibus engine xkb:us::eng; else ibus engine <engine-id>; fi'")
   ```
   Or leave bindings.lua untouched and use IBus's built-in **Ctrl+Space**, which
   cycles through everything in `preload-engines` — handy for several languages.
5. **Log out and back in** (apps capture the IM env at login).

Notes:

- Do **not** re-run `setup-ibus-avro.sh` for this — it is Avro-specific and resets
  `preload-engines`/`bindings.lua` to the Avro values. The base from
  `base-setup.sh` stays valid for any engine.
- If candidates ever show up as stray windows, append that engine's class to the
  regex in the `o.window(...)` rule in `hyprland.lua`.