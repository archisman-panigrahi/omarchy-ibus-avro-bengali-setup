# Omarchy IBus Avro setup

Set packages, config, and troubleshooting documentation for
[`README.md`](README.md).

## Layout

- `README.md` — step-by-step guide (install, env override, autostart, keybinding)
- `files/environment.d/99-ibus.conf` — systemd IM env override for `/etc/environment.d`
- `files/hypr/autostart-ibus.lua` — `o.exec_on_start("ibus start --type wayland")` snippet
- `files/hypr/bindings-ibus.lua` — `hl.unbind` + Super+Shift+Space Avro toggle snippet
- `files/hypr/windowrule-ibus.lua` — focus-stealing safety-net rule snippet