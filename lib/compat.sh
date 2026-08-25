#!/bin/bash
# Omarchy version detection and the paths/commands that moved between 3 and 4.
#
# Omarchy 4 ("quattro") changed the substrate underneath almost every setting:
# Hyprland's config became Lua, Waybar became the Quickshell-based Omarchy
# shell, mako and hypridle folded into that same shell, and a batch of commands
# were renamed. Rather than branch at every call site, the differences are
# collapsed here into variables and a handful of indirection functions, so the
# registry and the section menus stay version-agnostic.

# OMA_V is the Omarchy major version: 3 or 4.
OMA_V=4

_oma_detect_version() {
  local raw=""

  # The packaged version file is authoritative on both releases. Omarchy 4
  # installs to /usr/share and leaves ~/.local/share/omarchy as a symlink, so
  # either path resolves; check the canonical one first.
  local f
  for f in "${OMARCHY_PATH:-/usr/share/omarchy}/version" \
    "$HOME/.local/share/omarchy/version"; do
    [[ -r $f ]] && {
      raw=$(<"$f")
      break
    }
  done

  # Fall back to the CLI, which only Omarchy 4 answers in this form.
  [[ -z $raw ]] && raw=$(omarchy version 2>/dev/null)

  local major="${raw%%.*}"
  if [[ $major =~ ^[0-9]+$ ]]; then
    OMA_V="$major"
    return
  fi

  # Last resort: the config format itself. Only Omarchy 4 ships hyprland.lua.
  [[ -f "$HOME/.config/hypr/hyprland.lua" ]] && OMA_V=4 || OMA_V=3
}

# oma_v4 / oma_v3 read better at call sites than comparing the number.
oma_v4() { ((OMA_V >= 4)); }
oma_v3() { ((OMA_V < 4)); }

# oma_compat_init — resolve every version-dependent path. Called once at start,
# before hyprconf.sh and registry.sh read these variables.
oma_compat_init() {
  _oma_detect_version

  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
  [[ -d $OMARCHY_PATH ]] || OMARCHY_PATH="$HOME/.local/share/omarchy"

  OMA_HYPR_DIR="$HOME/.config/hypr"
  OMA_STATE_DIR="$HOME/.local/state/omarchy"
  OMA_SHELL_JSON="$HOME/.config/omarchy/shell.json"

  if oma_v4; then
    # Hyprland config is Lua. hyprconf.sh dispatches on the extension.
    OMA_EXT="lua"
    # "current" moved out of ~/.config, which is now purely user-authored.
    OMA_CURRENT_DIR="$OMA_STATE_DIR/current"
    # Toggle snippets Hyprland sources last are Lua too.
    OMA_TOGGLE_EXT="lua"
  else
    OMA_EXT="conf"
    OMA_CURRENT_DIR="$HOME/.config/omarchy/current"
    OMA_TOGGLE_EXT="conf"
  fi

  OMA_THEME_DIR="$OMA_CURRENT_DIR/theme"
  OMA_BACKGROUND="$OMA_CURRENT_DIR/background"

  OMA_LOOKNFEEL="$OMA_HYPR_DIR/looknfeel.$OMA_EXT"
  OMA_INPUT_CONF="$OMA_HYPR_DIR/input.$OMA_EXT"
  OMA_MONITORS="$OMA_HYPR_DIR/monitors.$OMA_EXT"
  OMA_BINDINGS="$OMA_HYPR_DIR/bindings.$OMA_EXT"
  OMA_AUTOSTART="$OMA_HYPR_DIR/autostart.$OMA_EXT"

  # These two are read by separate processes and stayed in .conf format.
  OMA_SUNSET="$OMA_HYPR_DIR/hyprsunset.conf"
  # hypridle is gone in Omarchy 4 — idle timeouts live in shell.json.
  OMA_HYPRIDLE="$OMA_HYPR_DIR/hypridle.conf"
}

# --- renamed commands --------------------------------------------------------
#
# Commands whose route changed in Omarchy 4. Callers use the logical name and
# get whichever route the running release understands.

# oma_cmd_line <logical-name> — the route this Omarchy release understands, as
# a bare string. Call sites splice it in unquoted so it splits into arguments:
#   oma_exec "Timezone updated" $(oma_cmd_line timezone)
#
# Only commands invoked from code shared by both generations live here; the
# version-specific modules (waybar.sh, bar.sh) call their own routes directly.
oma_cmd_line() {
  case "$1" in
  bar-toggle) oma_v4 && echo "omarchy toggle bar" || echo "omarchy toggle waybar" ;;
  audio-restart) oma_v4 && echo "omarchy restart audio" || echo "omarchy restart pipewire" ;;
  timezone) oma_v4 && echo "omarchy menu timezone" || echo "omarchy tz select" ;;
  # Omarchy 4 replaced the standalone TUIs with shell panels, summoned over the
  # same IPC the bar widgets use.
  mixer) oma_v4 && echo "omarchy shell shell toggle omarchy.audio" || echo "omarchy launch audio" ;;
  wifi-menu) oma_v4 && echo "omarchy shell shell toggle omarchy.network" || echo "omarchy launch wifi" ;;
  bt-menu) oma_v4 && echo "omarchy shell shell toggle omarchy.bluetooth" || echo "omarchy launch bluetooth" ;;
  *) return 1 ;;
  esac
}
