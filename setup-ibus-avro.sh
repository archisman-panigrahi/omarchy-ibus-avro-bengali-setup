#!/usr/bin/env bash
#
# setup-ibus-avro.sh — IBus + Avro Phonetic (Bengali) for Omarchy/Hyprland
#
# Installs `ibus` (official repo) and `ibus-avro-git` (AUR via yay), fixes the
# IM environment (overriding Omarchy's default fcitx env.d), patches the three
# Hyprland Lua files, and asks you to log out/in.
#
# Idempotent: safe to re-run. Existing omarchy-ibus-avro blocks are replaced,
# and files are backed up as <file>.bak.<timestamp>.
# See README.md for the full rationale.
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
# Helpers
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
step "Checking prerequisites (Omarchy + Hyprland + yay)..."
command -v yay >/dev/null 2>&1 || {
  echo "yay is required (AUR helper). Install it first, e.g.: sudo pacman -S --needed yay"
  exit 1
}
command -v hyprctl >/dev/null 2>&1 || warn "hyprctl not found — this guide targets Omarchy/Hyprland"

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
step "Installing ibus (official repo)..."
sudo pacman -S --needed --noconfirm ibus

AVRO_INSTALLED=0
if command -v pacman >/dev/null 2>&1 && pacman -Qq 2>/dev/null | grep -qE '^(ibus-avro|ibus-avro-git)$'; then
  AVRO_INSTALLED=1
fi

if [ "$AVRO_INSTALLED" -eq 0 ]; then
  step "Installing ibus-avro-git (AUR via yay)..."
  yay -S --needed --noconfirm ibus-avro-git
else
  ok "ibus-avro already installed — skipping AUR build"
fi

# ---------------------------------------------------------------------------
# 2. IBus engine config — fresh installs don't list Avro as a usable engine
#    until it's added to the preloaded/ordered engine lists.
# ---------------------------------------------------------------------------
step "Configuring IBus engines (English default, Bengali via Ctrl+Space)..."
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'ibus-avro']" 2>/dev/null \
    && ok "preload-engines = ['xkb:us::eng', 'ibus-avro']" \
    || warn "could not set preload-engines (run 'gsettings get org.freedesktop.ibus.general preload-engines' to check)"
  gsettings set org.freedesktop.ibus.general engines-order "['ibus-avro', 'xkb:us::eng']" 2>/dev/null \
    && ok "engines-order = ['ibus-avro', 'xkb:us::eng']"
else
  warn "gsettings not found — add 'ibus-avro' to org.freedesktop.ibus.general preload-engines manually."
fi

# ---------------------------------------------------------------------------
# 3. IM environment — must beat Omarchy's default fcitx env.d
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

# Apply to the running systemd user env (fixes the live session too)
systemctl --user set-environment GTK_IM_MODULE=wayland QT_IM_MODULES='wayland;ibus' \
  QT_IM_MODULE=ibus XMODIFIERS='@im=ibus' SDL_IM_MODULE=ibus GLFW_IM_MODULE=ibus INPUT_METHOD=ibus

if [[ -x /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator ]]; then
  echo "    IM vars the session would get (expect no 'fcitx'):"
  /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator \
    | grep -iE "im_module|xim|input_method|sdl_im" || true
fi

# ---------------------------------------------------------------------------
# 4. Hyprland Lua patches
# ---------------------------------------------------------------------------
step "Patching Hyprland Lua config ($HYPR_CFG)..."
mkdir -p "$HYPR_CFG"

# 3a. autostart.lua — start ibus via the Lua start hook (hyprland.conf is ignored in Lua mode)
AUTOSTART_BLOCK=$(cat <<'IBLOCK'
-- ---[BEGIN]|omarchy-ibus-avro
-- IBus (ibus-avro). This Hyprland setup runs the Lua main config; hyprland.conf's
-- exec-once/env are ignored. Do NOT use 'ibus-daemon -drx' (old GTK panel steals
-- focus and breaks typing). v2 panel renders candidates as compositor popups.
o.exec_on_start("ibus start --type wayland")
-- ---[END]|omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/autostart.lua" "autostart.lua" "$AUTOSTART_BLOCK"

# 3b. bindings.lua — bind the Avro toggle to Ctrl+Space (no Omarchy default on it)
BINDINGS_BLOCK=$(cat <<'IBLOCK'
-- >>> omarchy-ibus-avro
-- Toggle Bengali/English with Ctrl+Space.
o.bind("CTRL + SPACE", "IBus Avro toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = ibus-avro ]; then ibus engine xkb:us::eng; else ibus engine ibus-avro; fi'")
-- <<< omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/bindings.lua" "bindings.lua" "$BINDINGS_BLOCK"

# 3c. hyprland.lua — focus safety net for ibus windows
WINDOWRULE_BLOCK=$(cat <<'IBLOCK'
-- ---[BEGIN]|omarchy-ibus-avro
-- IBus candidate/menu windows must never tile or steal focus.
o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })
-- ---[END]|omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/hyprland.lua" "hyprland.lua" "$WINDOWRULE_BLOCK"

# ---------------------------------------------------------------------------
# 5. Reload (only if running inside a Hyprland session)
# ---------------------------------------------------------------------------
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  step "Reloading Hyprland config..."
  if hyprctl reload >/dev/null 2>&1; then ok "reloaded"; else warn "reload failed"; fi
  hyprctl configerrors
fi

# ---------------------------------------------------------------------------
# 6. Wrap up
# ---------------------------------------------------------------------------
step "Setup complete."
cat <<EOF

  Installed : ibus (avro already installed, or built from AUR as ibus-avro-git)
  Env file  : ${INSTALLED_ENV}
  Lua files : autostart.lua, bindings.lua, hyprland.lua

  You MUST log out and back in so the session env is captured with ibus
  (already-running apps keep the old fcitx env). After re-login ibus
  auto-starts and the tray icon appears; toggle Bengali with Ctrl+Space.
EOF

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  if read -r -p "$(printf '%s' "${YELLOW}Log out now? [y/N] ${RESET}")" ans; then
    case "${ans,,}" in
      y|yes) ok "Logging out..."; hyprctl exit ;;
      *) ok "Okay — log out manually when ready." ;;
    esac
  else
    ok "Run again from a terminal if you want it to log out for you."
  fi
else
  ok "Log out and back in when ready."
fi