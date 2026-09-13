-- Add to ~/.config/hypr/bindings.lua
--
-- Toggle between English and the IBus Avro Bengali engine.
-- SUPER+SPACE is taken by the launcher, so use SUPER+SHIFT+SPACE.
--
-- Omarchy binds SUPER+SHIFT+SPACE to "Toggle top bar"
-- (default/hypr/bindings/utilities.lua). Hyprland fires EVERY matching binding,
-- so the top bar would toggle AND the engine would switch. Unbind it first.
hl.unbind("SUPER + SHIFT + SPACE")
o.bind("SUPER + SHIFT + SPACE", "IBus Avro toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = ibus-avro ]; then ibus engine xkb:us::eng; else ibus engine ibus-avro; fi'")