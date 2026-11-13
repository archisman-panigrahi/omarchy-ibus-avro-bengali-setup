#!/usr/bin/env bash
#
# setup-ibus-avro.sh — IBus + Avro Phonetic (Bengali) for Omarchy/Hyprland
#
# Installs `ibus` (official repo) and `ibus-avro-git` (AUR via yay), disables
# Omarchy's fcitx5 user service (it owns org.freedesktop.IBus and blocks
# ibus-daemon), fixes the IM environment (overriding Omarchy's default fcitx
# env.d), patches the three Hyprland Lua files, and asks you to log out/in.
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

# upsert: replace every "[BEGIN]|tag ... [END]|tag" block in $1 with $2.
# $3/$4 override the markers (defaults: the shared BEGIN_MARK/END_MARK). Removing
# *all* matching blocks is what de-duplicates files left by older script versions.
upsert() {
  local file="$1" block="$2" b="${3:-$BEGIN_MARK}" e="${4:-$END_MARK}" tmp
  tmp="$(mktemp)"
  awk -v b="$b" -v e="$e" '
    !inskip && index($0, b) { inskip = 1; next }
    inskip && index($0, e)  { inskip = 0; next }
    !inskip { print }
  ' "$file" > "$tmp"
  { cat "$tmp"; printf '%s\n' "$block"; } > "$file"
  rm -f "$tmp"
}

append_block() { # $1 file, $2 description, $3 block, [$4 begin mark, $5 end mark]
  local file="$1" desc="$2" block="$3" b="${4:-$BEGIN_MARK}" e="${5:-$END_MARK}"
  if [[ -f "$file" ]]; then
    backup "$file"
    if grep -qF -- "$b" "$file"; then
      upsert "$file" "$block" "$b" "$e"
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
# 2. Disable fcitx5 — Omarchy starts it as a systemd user service, and its
#    ibusfrontend addon claims org.freedesktop.IBus on the session bus. While
#    that name is taken, ibus-daemon cannot start: `ibus` commands talk to
#    fcitx5 instead, so Avro never appears. Disable it for this user account.
# ---------------------------------------------------------------------------
step "Disabling fcitx5 (it claims org.freedesktop.IBus and blocks IBus)..."
FCITX_UNIT="omarchy-fcitx5.service"

if systemctl --user cat "$FCITX_UNIT" >/dev/null 2>&1; then
  systemctl --user disable --now "$FCITX_UNIT" >/dev/null 2>&1 || true
  if systemctl --user is-active "$FCITX_UNIT" >/dev/null 2>&1; then
    warn "could not stop $FCITX_UNIT — run: systemctl --user stop $FCITX_UNIT"
  elif systemctl --user is-enabled "$FCITX_UNIT" >/dev/null 2>&1; then
    warn "could not disable $FCITX_UNIT — run: systemctl --user disable $FCITX_UNIT"
  else
    ok "disabled and stopped $FCITX_UNIT"
    ok "re-enable later with: systemctl --user enable --now $FCITX_UNIT"
  fi
else
  warn "$FCITX_UNIT not found — fcitx5 may be started another way"
fi

# If fcitx5 is running outside the unit (e.g. an XDG autostart path), stop it
# so the IBus bus name is free right now.
if pgrep -x fcitx5 >/dev/null 2>&1; then
  warn "fcitx5 is still running — stopping it for this session"
  pkill -x fcitx5 2>/dev/null || true
  sleep 1
fi

# Hide the XDG autostart entry as well, in case the session starts it directly.
AUTOSTART_FILE="$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
if ! grep -qxF 'Hidden=true' "$AUTOSTART_FILE" 2>/dev/null; then
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  if [[ ! -f "$AUTOSTART_FILE" ]]; then
    printf '[Desktop Entry]\nHidden=true\n' > "$AUTOSTART_FILE"
  elif grep -qE '^Hidden=' "$AUTOSTART_FILE"; then
    sed -i 's/^Hidden=.*/Hidden=true/' "$AUTOSTART_FILE"
  else
    printf 'Hidden=true\n' >> "$AUTOSTART_FILE"
  fi
  ok "hid fcitx5 XDG autostart entry"
else
  ok "fcitx5 XDG autostart already hidden"
fi

# ---------------------------------------------------------------------------
# 3. IBus engine config — fresh installs don't list Avro as a usable engine
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
# 4. IM environment — must beat Omarchy's default fcitx env.d
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
# 5. Hyprland Lua patches
# ---------------------------------------------------------------------------
step "Patching Hyprland Lua config ($HYPR_CFG)..."
mkdir -p "$HYPR_CFG"

# 5a. autostart.lua — start ibus via the Lua start hook (hyprland.conf is ignored in Lua mode)
# Remove any legacy `ibus-daemon -drx` autostart line FIRST: it survives restores
# and would race our wayland start (old X11 panel, no proper tray/SNI icon).
if [ -f "$HYPR_CFG/autostart.lua" ] && grep -q 'o.exec_on_start("ibus-daemon' "$HYPR_CFG/autostart.lua" 2>/dev/null; then
  sed -i '/o\.exec_on_start("ibus-daemon/d' "$HYPR_CFG/autostart.lua"
  ok "removed legacy ibus-daemon autostart line"
fi
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

# 5b. bindings.lua — bind the Avro toggle to Ctrl+Space (no Omarchy default on it)
BINDINGS_BLOCK=$(cat <<'IBLOCK'
-- >>> omarchy-ibus-avro
-- Toggle Bengali/English with Ctrl+Space.
o.bind("CTRL + SPACE", "IBus Avro toggle", "sh -c 'e=$(ibus engine); if [ \"$e\" = ibus-avro ]; then ibus engine xkb:us::eng; else ibus engine ibus-avro; fi'")
-- <<< omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/bindings.lua" "bindings.lua" "$BINDINGS_BLOCK" \
  "-- >>> omarchy-ibus-avro" "-- <<< omarchy-ibus-avro"

# 5c. hyprland.lua — focus safety net for ibus windows
WINDOWRULE_BLOCK=$(cat <<'IBLOCK'
-- ---[BEGIN]|omarchy-ibus-avro
-- IBus candidate/menu windows must never tile or steal focus.
o.window("(ibus|IBus|Avro|avro|org\\.freedesktop\\.IBus)", { float = true, no_focus = true })
-- ---[END]|omarchy-ibus-avro
IBLOCK
)
append_block "$HYPR_CFG/hyprland.lua" "hyprland.lua" "$WINDOWRULE_BLOCK"

# ---------------------------------------------------------------------------
# 6. Reload (only if running inside a Hyprland session)
# ---------------------------------------------------------------------------
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  # Start IBus now that fcitx5 no longer owns org.freedesktop.IBus, so newly
  # launched apps work without waiting for a logout.
  if ! pgrep -x ibus-daemon >/dev/null 2>&1; then
    if ibus start --type wayland >/dev/null 2>&1; then
      ok "started ibus-daemon"
    else
      warn "could not start ibus-daemon — it will start at next login"
    fi
  fi

  step "Reloading Hyprland config..."
  if hyprctl reload >/dev/null 2>&1; then ok "reloaded"; else warn "reload failed"; fi
  hyprctl configerrors
fi

# ---------------------------------------------------------------------------
# 7. Wrap up
# ---------------------------------------------------------------------------
step "Setup complete."
cat <<EOF

  Installed : ibus (avro already installed, or built from AUR as ibus-avro-git)
  Env file  : ${INSTALLED_ENV}
  Lua files : autostart.lua, bindings.lua, hyprland.lua
  Fcitx5    : disabled for this user (restore with: systemctl --user enable --now omarchy-fcitx5.service)

  You MUST log out and back in so the session env is captured with ibus
  (already-running apps keep the old fcitx env). After re-login ibus
  auto-starts and the tray icon appears; toggle Bengali with Ctrl+Space.
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