#!/bin/bash
# Feature toggles, with live state read the same way Omarchy itself reads it.

# Omarchy stores these as "-off" flag files, so a present flag means disabled.
_toggle_flag_state() {
  [[ -f "$OMA_STATE_DIR/toggles/$1" ]] && printf 'off' || printf 'on'
}

_toggle_proc_state() { pgrep -x "$1" >/dev/null 2>&1 && printf 'on' || printf 'off'; }

_toggle_nightlight_state() {
  pgrep -x hyprsunset >/dev/null 2>&1 || {
    printf 'off'
    return
  }
  local t
  t=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [[ -n $t && $t -lt 5500 ]] && printf 'on' || printf 'off'
}

_toggle_dnd_state() {
  oma_has makoctl || {
    printf '?'
    return
  }
  makoctl mode 2>/dev/null | grep -q 'do-not-disturb' && printf 'on' || printf 'off'
}

_toggle_touch_state() {
  # omarchy-toggle-touchpad/touchscreen drop a Hyprland snippet when disabled.
  compgen -G "$OMA_STATE_DIR/toggles/hypr/$1-disabled.conf" >/dev/null 2>&1 &&
    printf 'off' || printf 'on'
}

toggles_menu() {
  while true; do
    oma_screen "Toggles"

    local -a entries=()
    entries+=("$(printf 'waybar\tStatus bar (Waybar)\t%s' "$(_toggle_proc_state waybar)")")
    entries+=("$(printf 'idle\tIdle lock (hypridle)\t%s' "$(_toggle_proc_state hypridle)")")
    entries+=("$(printf 'nightlight\tNight light\t%s' "$(_toggle_nightlight_state)")")
    entries+=("$(printf 'screensaver\tScreensaver\t%s' "$(_toggle_flag_state screensaver-off)")")
    entries+=("$(printf 'suspend\tSuspend in system menu\t%s' "$(_toggle_flag_state suspend-off)")")
    entries+=("$(printf 'dnd\tDo not disturb\t%s' "$(_toggle_dnd_state)")")
    entries+=("$(printf 'touchpad\tTouchpad\t%s' "$(_toggle_touch_state touchpad)")")
    entries+=("$(printf 'touchscreen\tTouchscreen\t%s' "$(_toggle_touch_state touchscreen)")")
    oma_has supergfxctl &&
      entries+=("$(printf 'gpu\tHybrid GPU mode\t%s' "$(supergfxctl -g 2>/dev/null)")")
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Enter toggles the highlighted feature" "${entries[@]}") || return 0
    [[ $choice == back ]] && return 0

    printf '\n'
    case "$choice" in
    dnd) oma_spin "Do not disturb toggled" omarchy toggle notification silencing ;;
    gpu) oma_spin "Hybrid GPU toggled" omarchy toggle hybrid gpu ;;
    *) oma_spin "${choice} toggled" omarchy toggle "$choice" ;;
    esac
    sleep 0.6
  done
}
