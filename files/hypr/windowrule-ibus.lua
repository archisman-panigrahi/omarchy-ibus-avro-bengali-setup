-- Add to ~/.config/hypr/hyprland.lua
--
-- Safety-net window rule so ibus candidate/menu windows never tile or steal
-- focus. With the input-method protocol v2 panel they are compositor popups
-- already; this guards XWayland/XIM fallbacks so typing is never interrupted.
o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })