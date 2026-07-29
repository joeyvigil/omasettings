#!/bin/bash
# Declarative registry of every Hyprland-backed setting.
#
# One record per setting, pipe separated:
#   section|label|file|config-section|key|live-option|kind|choices
#
# Section menus render from this, global search matches against it, and the
# "changed from defaults" view walks it. Adding a setting here makes it appear
# in all three at once.

OMA_SETTINGS=(
  # --- appearance ---
  "appearance|Corner rounding|$OMA_LOOKNFEEL|decoration|rounding|decoration:rounding|int|"
  "appearance|Dim inactive windows|$OMA_LOOKNFEEL|decoration|dim_inactive|decoration:dim_inactive|bool|"
  "appearance|Dim strength|$OMA_LOOKNFEEL|decoration|dim_strength|decoration:dim_strength|float|"
  "appearance|Active window opacity|$OMA_LOOKNFEEL|decoration|active_opacity|decoration:active_opacity|float|"
  "appearance|Inactive window opacity|$OMA_LOOKNFEEL|decoration|inactive_opacity|decoration:inactive_opacity|float|"
  "appearance|Blur|$OMA_LOOKNFEEL|decoration.blur|enabled|decoration:blur:enabled|bool|"
  "appearance|Blur size|$OMA_LOOKNFEEL|decoration.blur|size|decoration:blur:size|int|"
  "appearance|Blur passes|$OMA_LOOKNFEEL|decoration.blur|passes|decoration:blur:passes|int|"
  "appearance|Window shadows|$OMA_LOOKNFEEL|decoration.shadow|enabled|decoration:shadow:enabled|bool|"

  # --- look & feel ---
  "looknfeel|Inner gaps|$OMA_LOOKNFEEL|general|gaps_in|general:gaps_in|int|"
  "looknfeel|Outer gaps|$OMA_LOOKNFEEL|general|gaps_out|general:gaps_out|int|"
  "looknfeel|Border size|$OMA_LOOKNFEEL|general|border_size|general:border_size|int|"
  "looknfeel|Resize on border drag|$OMA_LOOKNFEEL|general|resize_on_border|general:resize_on_border|bool|"
  "looknfeel|Tiling layout|$OMA_LOOKNFEEL|general|layout|general:layout|choice|dwindle master scrolling"
  "looknfeel|Animations|$OMA_LOOKNFEEL|animations|enabled|animations:enabled|bool|"
  "looknfeel|Single-window aspect ratio|$OMA_LOOKNFEEL|layout|single_window_aspect_ratio|layout:single_window_aspect_ratio|str|"
  "looknfeel|Scrolling column width|$OMA_LOOKNFEEL|scrolling|column_width|scrolling:column_width|float|"

  # --- input ---
  "input|Keyboard layout|$OMA_INPUT_CONF|input|kb_layout|input:kb_layout|str|"
  "input|Keyboard variant|$OMA_INPUT_CONF|input|kb_variant|input:kb_variant|str|"
  "input|Keyboard options|$OMA_INPUT_CONF|input|kb_options|input:kb_options|str|"
  "input|Key repeat rate|$OMA_INPUT_CONF|input|repeat_rate|input:repeat_rate|int|"
  "input|Key repeat delay|$OMA_INPUT_CONF|input|repeat_delay|input:repeat_delay|int|"
  "input|Numlock on boot|$OMA_INPUT_CONF|input|numlock_by_default|input:numlock_by_default|bool|"
  "input|Mouse sensitivity|$OMA_INPUT_CONF|input|sensitivity|input:sensitivity|float|"
  "input|Mouse acceleration|$OMA_INPUT_CONF|input|accel_profile|input:accel_profile|choice|adaptive flat"
  "input|Focus follows mouse|$OMA_INPUT_CONF|input|follow_mouse|input:follow_mouse|choice|0 1 2 3"

  # --- touchpad ---
  "touchpad|Natural scrolling|$OMA_INPUT_CONF|input.touchpad|natural_scroll|input:touchpad:natural_scroll|bool|"
  "touchpad|Two-finger right click|$OMA_INPUT_CONF|input.touchpad|clickfinger_behavior|input:touchpad:clickfinger_behavior|bool|"
  "touchpad|Scroll speed|$OMA_INPUT_CONF|input.touchpad|scroll_factor|input:touchpad:scroll_factor|float|"
  "touchpad|Disable while typing|$OMA_INPUT_CONF|input.touchpad|disable_while_typing|input:touchpad:disable_while_typing|bool|"
  "touchpad|Tap to click|$OMA_INPUT_CONF|input.touchpad|tap-to-click|input:touchpad:tap-to-click|bool|"
  "touchpad|Three-finger drag|$OMA_INPUT_CONF|input.touchpad|drag_3fg|input:touchpad:drag_3fg|choice|0 1 2"
)

# Human-readable name for each registry section, used by search results.
oma_reg_section_name() {
  case "$1" in
  appearance) printf 'Appearance' ;;
  looknfeel) printf 'Look & Feel' ;;
  input) printf 'Input' ;;
  touchpad) printf 'Input › Touchpad' ;;
  *) printf '%s' "$1" ;;
  esac
}

_oma_reg_read() {
  IFS='|' read -r r_section r_label r_file r_hsec r_key r_live r_kind r_choices \
    <<<"${OMA_SETTINGS[$1]}"
}

# Menu entries (key<TAB>label<TAB>current value) for one section.
oma_reg_entries() {
  local want="$1" i
  local r_section r_label r_file r_hsec r_key r_live r_kind r_choices
  for i in "${!OMA_SETTINGS[@]}"; do
    _oma_reg_read "$i"
    [[ $r_section == "$want" ]] || continue
    printf '%s\t%s\t%s\n' "reg:$i" "$r_label" \
      "$(hypr_show "$r_file" "$r_hsec" "$r_key" "$r_live" "$r_kind")"
  done
}

# Open the editor for one registry index.
oma_reg_edit() {
  local r_section r_label r_file r_hsec r_key r_live r_kind r_choices
  _oma_reg_read "$1"
  # shellcheck disable=SC2086  # choices are intentionally split into arguments
  hypr_edit "$r_file" "$r_hsec" "$r_key" "$r_live" "$r_kind" "$r_label" $r_choices
}

# Indices whose key is actively set in the user's config, i.e. customized away
# from whatever Omarchy ships.
oma_reg_customized() {
  local i
  local r_section r_label r_file r_hsec r_key r_live r_kind r_choices
  for i in "${!OMA_SETTINGS[@]}"; do
    _oma_reg_read "$i"
    [[ -n $(hypr_get "$r_file" "$r_hsec" "$r_key") ]] && printf '%s\n' "$i"
  done
}
