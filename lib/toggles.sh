#!/bin/bash
# Feature toggles, with live state read the same way Omarchy itself reads it.

# Omarchy stores these as "-off" flag files, so a present flag means disabled.
_toggle_flag_state() {
  [[ -f "$OMA_STATE_DIR/toggles/$1" ]] && printf 'off' || printf 'on'
}

_toggle_proc_state() { pgrep -x "$1" >/dev/null 2>&1 && printf 'on' || printf 'off'; }

# Omarchy 3 draws the bar with Waybar, so the process is the state. Omarchy 4
# draws it inside the long-running shell and hides it with a flag file instead,
# so the shell still runs with the bar switched off.
_toggle_bar_state() {
  if oma_v4; then _toggle_flag_state bar-off; else _toggle_proc_state waybar; fi
}

# Omarchy 4 dropped hypridle: idle is handled by the shell, and the toggle
# parks it in a "stay awake" state recorded as an indicator flag.
_toggle_idle_state() {
  if oma_v4; then
    [[ -f "$OMA_STATE_DIR/indicators/stay-awake" ]] && printf 'off' || printf 'on'
  else
    _toggle_proc_state hypridle
  fi
}

# Below Omarchy's own identity temperature the screen is actually being warmed.
_toggle_nightlight_state() {
  pgrep -x hyprsunset >/dev/null 2>&1 || {
    printf 'off'
    return
  }
  local t
  t=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [[ -n $t && $t -lt 6000 ]] && printf 'on' || printf 'off'
}

_toggle_dnd_state() {
  if oma_v4; then
    local v
    v=$(shell_ipc notifications dndState)
    case "$v" in
    on | off) printf '%s' "$v" ;;
    *) [[ $(jq -r '.dnd // false' "$OMA_STATE_DIR/notifications.json" 2>/dev/null) == true ]] &&
      printf 'on' || printf 'off' ;;
    esac
  else
    oma_has makoctl || {
      printf '?'
      return
    }
    makoctl mode 2>/dev/null | grep -q 'do-not-disturb' && printf 'on' || printf 'off'
  fi
}

_toggle_touch_state() {
  # omarchy-toggle-touchpad/touchscreen drop a Hyprland snippet when disabled;
  # it is .conf on Omarchy 3 and .lua on 4.
  compgen -G "$OMA_STATE_DIR/toggles/hypr/$1-disabled.$OMA_TOGGLE_EXT" >/dev/null 2>&1 &&
    printf 'off' || printf 'on'
}

toggles_menu() {
  while true; do
    oma_screen "Toggles"

    local -a entries=()
    # Naming the program is only informative on Omarchy 3, where it is a
    # separate one; on 4 the bar is just part of the shell.
    local bar_label="Status bar"
    oma_v4 || bar_label="Status bar (Waybar)"
    entries+=("$(printf 'bar\t%s\t%s' "$bar_label" "$(_toggle_bar_state)")")
    entries+=("$(printf 'idle\tIdle lock\t%s' "$(_toggle_idle_state)")")
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
    # `omarchy toggle bar` on Omarchy 4, `omarchy toggle waybar` on 3.
    bar) oma_spin "$(oma_bar_label) toggled" $(oma_cmd_line bar-toggle) ;;
    *) oma_spin "${choice} toggled" omarchy toggle "$choice" ;;
    esac
    sleep 0.6
  done
}
