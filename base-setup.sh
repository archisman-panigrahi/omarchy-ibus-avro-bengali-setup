#!/usr/bin/env bash
#
# base-setup.sh — engine-agnostic IBus foundation for Omarchy/Hyprland
#
# Installs `ibus` itself, fixes the IM environment (overriding Omarchy's default
# fcitx env.d), starts ibus in Wayland mode via autostart.lua, and adds the
# focus safety-net window rule to hyprland.lua.
#
# This does NOT pick a language/engine — that part is engine-specific. After
# running this, install your engine (e.g. `yay -S ibus-m17n`), find its ID via
# `ibus list-engine`, then follow other-engines.md for the preload + keybinding.
#
# Idempotent: safe to re-run. Uses the same marker tags as setup-ibus-avro.sh
# (`- ---[BEGIN]|omarchy-ibus-avro`), so both scripts interoperate — running one
# after the other won't duplicate blocks.
#
# See README.md / details.md for the rationale.
#
set -euo pipefail

CYAN=$'\e[36m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

step() { printf '%s\n' "${BOLD}==>${RESET} $*"; }
ok()   { printf '%s\n' "${GREEN}    OK${RESET} $*"; }
warn() { printf '%s\n' "${YELLOW}    !! $*${RESET}" >&2; }

HYPR_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

BEGIN_MARK="---[BEGIN]|omarchy-ibus-avro"
END_MARK="---[END]|omarchy-ibus-avro"

# ---------------------------------------------------------------------------
# Helpers (same as setup-ibus-avro.sh)
# ---------------------------------------------------------------------------

backup() { # $1 file — make one .bak.<timestamp> copy per run
  local f="$1" bk
  [[ -f "$f" ]] || return 0
  bk="$f.bak.$(date +%s)"
  cp -a "$f" "$bk" && ok "backed up $f -> $bk"
}

# upsert: replace an existing "[BEGIN]|tag ... [END]|tag" block in $1 with $2
upsert() {
  local file="$1" block="$2" tmp
  tmp="$(mktemp)"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    !inskip && index($0, b) { inskip = 1; next }
    inskip && index($0, e)  { inskip = 0; next }
    !inskip { print }
  ' "$file" > "$tmp"
  { cat "$tmp"; printf '%s\n' "$block"; } > "$file"
  rm -f "$tmp"
}

append_block() { # $1 file, $2 description, $3 block
  local file="$1" desc="$2" block="$3" backup_done=""
  if [[ -f "$file" ]]; then
    backup "$file"
    if grep -qF -- "$BEGIN_MARK" "$file"; then
      upsert "$file" "$block"
      ok "updated $desc ($file)"
    else
      printf '\n%s\n' "$block" >> "$file"
      ok "appended to $desc ($file)"
    fi
  else
    printf '%s\n' "$block" > "$file"
    ok "created $desc ($file)"
  fi
}

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
step "Checking prerequisites (Omarchy + Hyprland)..."
command -v hyprctl >/dev/null 2>&1 || warn "hyprctl not found — this targets Omarchy/Hyprland"

# ---------------------------------------------------------------------------
# 1. Base package
# ---------------------------------------------------------------------------
step "Installing ibus (official repo)..."
sudo pacman -S --needed --noconfirm ibus

# ---------------------------------------------------------------------------
# 2. IM environment — must beat Omarchy's default fcitx env.d
#    (/usr/lib/environment.d/10-omarchy-fcitx.conf). /etc is applied last.
# ---------------------------------------------------------------------------
step "Writing IM environment override..."

ENV_FILE_CONTENT=$(cat <<'EOF'
GTK_IM_MODULE=wayland
QT_IM_MODULES=wayland;ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
SDL_IM_MODULE=ibus
GLFW_IM_MODULE=ibus
INPUT_METHOD=ibus
EOF
)

INSTALLED_ENV=""
if sudo install -o root -g root -m 0644 -D /dev/stdin /etc/environment.d/99-ibus.conf \
   <<<"$ENV_FILE_CONTENT" 2>/dev/null; then
  INSTALLED_ENV="/etc/environment.d/99-ibus.conf"
  ok "wrote /etc/environment.d/99-ibus.conf"
else
  warn "Could not write /etc/environment.d (need sudo)."
  warn "Falling back to ~/.config/environment.d — note this may still be overridden"
  warn "by /usr/lib/environment.d/10-omarchy-fcitx.conf on some systemd builds."
  mkdir -p "$HOME/.config/environment.d"
  printf '# Override Omarchy\'"'"'s fcitx env.d if needed\n%s\n' "$ENV_FILE_CONTENT" \
    > "$HOME/.config/environment.d/10-ibus.conf"
  INSTALLED_ENV="$HOME/.config/environment.d/10-ibus.conf"
fi

systemctl --user set-environment GTK_IM_MODULE=wayland QT_IM_MODULES='wayland;ibus' \
  QT_IM_MODULE=ibus XMODIFIERS='@im=ibus' SDL_IM_MODULE=ibus GLFW_IM_MODULE=ibus INPUT_METHOD=ibus

if [[ -x /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator ]]; then
  echo "    IM vars the session would get (expect no 'fcitx'):"
  /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator \
    | grep -iE "im_module|xim|input_method|sdl_im" || true
fi

# ---------------------------------------------------------------------------
# 3. Hyprland Lua patches (generic, engine-agnostic)
# ---------------------------------------------------------------------------
step "Patching Hyprland Lua config ($HYPR_CFG)..."
mkdir -p "$HYPR_CFG"

# 3a. autostart.lua — start ibus via the Lua start hook (hyprland.conf is ignored in Lua mode)
# Remove any legacy `ibus-daemon -drx` autostart line FIRST: it survives restores
# and would race our wayland start (old X11 panel, no proper tray/SNI icon).
if [ -f "$HYPR_CFG/autostart.lua" ] && grep -q 'o.exec_on_start("ibus-daemon' "$HYPR_CFG/autostart.lua" 2>/dev/null; then
  sed -i '/o\.exec_on_start("ibus-daemon/d' "$HYPR_CFG/autostart.lua"
  ok "removed legacy ibus-daemon autostart line"
fi
AUTOSTART_BLOCK=$(cat <<'IBLOCK'
-- ---[BEGIN]|omarchy-ibus-avro
-- IBus. This Hyprland setup runs the Lua main config; hyprland.conf's
-- exec-once/env are ignored. Do NOT use 'ibus-daemon -drx' (old GTK panel steals
-- focus and breaks typing). v2 panel renders candidates as compositor popups.
o.exec_on_start("ibus start --type wayland")
-- ---[END]|omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/autostart.lua" "autostart.lua" "$AUTOSTART_BLOCK"

# 3b. hyprland.lua — focus safety net for ibus windows (any engine)
WINDOWRULE_BLOCK=$(cat <<'IBLOCK'
-- ---[BEGIN]|omarchy-ibus-avro
-- IBus candidate/menu windows must never tile or steal focus.
o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })
-- ---[END]|omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/hyprland.lua" "hyprland.lua" "$WINDOWRULE_BLOCK"

# ---------------------------------------------------------------------------
# 4. Reload (only if running inside a Hyprland session)
# ---------------------------------------------------------------------------
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  step "Reloading Hyprland config..."
  if hyprctl reload >/dev/null 2>&1; then ok "reloaded"; else warn "reload failed"; fi
  hyprctl configerrors
fi

# ---------------------------------------------------------------------------
# 5. Wrap up
# ---------------------------------------------------------------------------
step "Base setup complete."
cat <<EOF

  Installed : ibus
  Env file  : ${INSTALLED_ENV}
  Lua files : autostart.lua, hyprland.lua (engine-agnostic)

  Base IBus + Omarchy wiring is now in place. Engine-specific parts are NOT
  done here — see other-engines.md:
      yay -S --needed ibus-m17n          # or your engine
      ibus list-engine                    # find the ID
      ... steps 3 & 4 (gsettings preload + Ctrl+Space toggle) ...

  Log out and back in so the session env is captured with ibus
  (already-running apps keep the old fcitx env).
EOF

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  if read -r -p "$(printf '%s' "${YELLOW}Log out now? [y/N] ${RESET}")" ans; then
    case "${ans,,}" in
      y|yes)
        ok "Logging out..."
        if command -v uwsm >/dev/null 2>&1; then
          uwsm stop
        else
          hyprctl dispatch exit
        fi
        ;;
      *) ok "Okay — log out manually when ready." ;;
    esac
  else
    ok "Run again from a terminal if you want it to log out for you."
  fi
else
  ok "Log out and back in when ready."
fi