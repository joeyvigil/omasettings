#!/bin/bash
# Display: monitors, brightness, and night light.

_display_brightness() {
  while true; do
    oma_screen "Display › Brightness"
    local level=""
    oma_has brightnessctl && level="$(brightnessctl -m 2>/dev/null | cut -d, -f4)"

    local choice
    choice=$(oma_select "Display brightness${level:+ — $level}" \
      $'up\tBrighter (+10%)\t' \
      $'down\tDimmer (-10%)\t' \
      $'set\tSet an exact level…\t' \
      $'kbd\tKeyboard backlight\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    up) omarchy brightness display "+10%" >/dev/null 2>&1 ;;
    down) omarchy brightness display "10%-" >/dev/null 2>&1 ;;
    set)
      local pct
      pct=$(gum input --header "Brightness percentage (1–100)" --placeholder "60") || continue
      [[ $pct =~ ^[0-9]+$ ]] || {
        oma_err "not a number"
        oma_pause
        continue
      }
      printf '\n'
      oma_spin "Brightness set to $pct%" omarchy brightness display "$pct%"
      sleep 0.4
      ;;
    kbd)
      printf '\n'
      oma_spin "Keyboard backlight cycled" omarchy brightness keyboard cycle
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}

_display_nightlight() {
  while true; do
    oma_screen "Display › Night light"

    local temp="unknown"
    if oma_hypr_live && pgrep -x hyprsunset >/dev/null 2>&1; then
      temp=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -1)
      [[ -n $temp ]] && temp="${temp}K" || temp="unknown"
    else
      temp="hyprsunset not running"
    fi

    local choice
    choice=$(oma_select "Night light — $temp" \
      $'toggle\tToggle night light now\t' \
      $'edit\tEdit the hyprsunset schedule\t' \
      $'restart\tRestart hyprsunset\t' \
      $'reset\tReset hyprsunset to defaults\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    toggle)
      printf '\n'
      oma_spin "Night light toggled" omarchy toggle nightlight
      sleep 0.5
      ;;
    edit)
      oma_edit_file "$OMA_SUNSET" && oma_spin "hyprsunset restarted" omarchy restart hyprsunset
      sleep 0.4
      ;;
    restart)
      printf '\n'
      oma_spin "hyprsunset restarted" omarchy restart hyprsunset
      sleep 0.4
      ;;
    reset)
      oma_confirm "Reset hyprsunset config to the Omarchy default?" &&
        oma_exec "hyprsunset reset" omarchy refresh hyprsunset
      ;;
    back | *) return 0 ;;
    esac
  done
}

display_menu() {
  while true; do
    oma_screen "Display"

    local count=""
    oma_hypr_live && count="$(hyprctl -j monitors 2>/dev/null | jq -r 'length' 2>/dev/null) connected"

    local choice
    choice=$(oma_select "Monitors, brightness, and night light" \
      "$(printf 'monitors\tMonitors…\t%s' "$count")" \
      $'brightness\tBrightness…\t' \
      $'night\tNight light…\t' \
      $'lock\tEdit lock screen (hyprlock)\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    monitors) monitors_menu ;;
    brightness) _display_brightness ;;
    night) _display_nightlight ;;
    lock)
      oma_edit_file "$OMA_HYPR_DIR/hyprlock.conf"
      sleep 0.2
      ;;
    back | *) return 0 ;;
    esac
  done
}
