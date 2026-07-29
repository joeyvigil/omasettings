#!/bin/bash
# Power: profiles, idle behaviour, and hibernation.

_power_profile() {
  oma_has powerprofilesctl || {
    oma_err "powerprofilesctl is not installed"
    oma_pause
    return 1
  }

  local -a profiles=()
  mapfile -t profiles < <(omarchy powerprofiles list 2>/dev/null)
  ((${#profiles[@]})) || {
    oma_err "no power profiles available"
    oma_pause
    return 1
  }

  local current choice
  current=$(powerprofilesctl get 2>/dev/null)
  choice=$(oma_pick "Power profile — current: ${current:-unknown}" "$current" \
    "${profiles[@]}" "autodetect (follow AC/battery)") || return 0
  [[ -z $choice ]] && return 0

  printf '\n'
  if [[ $choice == autodetect* ]]; then
    oma_spin "Power profile follows AC/battery" omarchy powerprofiles set autodetect
  else
    oma_spin "Power profile set to $choice" powerprofilesctl set "$choice"
  fi
  sleep 0.4
}

_power_idle() {
  while true; do
    oma_screen "Power › Idle & lock"

    local running
    running=$(pgrep -x hypridle >/dev/null 2>&1 && printf 'running' || printf 'stopped')

    local choice
    choice=$(oma_select "Idle behaviour — hypridle is $running" \
      "$(printf 'toggle\tToggle idle locking\t%s' "$running")" \
      $'edit\tEdit idle timeouts (hypridle.conf)\t' \
      $'restart\tRestart hypridle\t' \
      $'reset\tReset hypridle to defaults\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    toggle)
      printf '\n'
      oma_spin "Idle locking toggled" omarchy toggle idle
      sleep 0.6
      ;;
    edit)
      oma_edit_file "$OMA_HYPRIDLE" && oma_spin "hypridle restarted" omarchy restart hypridle
      sleep 0.4
      ;;
    restart)
      printf '\n'
      oma_spin "hypridle restarted" omarchy restart hypridle
      sleep 0.4
      ;;
    reset)
      oma_confirm "Reset hypridle config to the Omarchy default?" &&
        oma_exec "hypridle reset" omarchy refresh hypridle
      ;;
    back | *) return 0 ;;
    esac
  done
}

power_menu() {
  while true; do
    oma_screen "Power"

    local profile="" battery=""
    oma_has powerprofilesctl && profile=$(powerprofilesctl get 2>/dev/null)
    # battery status is a long glyph-laden string built for Waybar; the menu
    # column only has room for the percentage.
    if omarchy battery present >/dev/null 2>&1; then
      battery="$(omarchy battery remaining 2>/dev/null)%"
    fi

    local choice
    choice=$(oma_select "Power profile, idle behaviour, hibernation" \
      "$(printf 'profile\tPower profile\t%s' "$profile")" \
      $'idle\tIdle & lock…\t' \
      "$(printf 'battery\tBattery\t%s' "$battery")" \
      $'hibernate\tHibernation\t' \
      $'suspend\tSuspend in system menu\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    profile) _power_profile ;;
    idle) _power_idle ;;
    battery)
      oma_screen "Power › Battery"
      if omarchy battery present >/dev/null 2>&1; then
        oma_dim "Charge:    $(omarchy battery remaining 2>/dev/null)%"
        oma_dim "Status:    $(omarchy battery status 2>/dev/null)"
        oma_dim "Remaining: $(omarchy battery remaining time 2>/dev/null)"
        oma_dim "Capacity:  $(omarchy battery capacity 2>/dev/null) Wh"
      else
        oma_dim "No battery detected on this system."
      fi
      oma_pause
      ;;
    hibernate)
      oma_screen "Power › Hibernation"
      if omarchy hibernation available >/dev/null 2>&1; then
        oma_dim "Hibernation is currently set up."
        printf '\n'
        oma_confirm "Remove hibernation support?" &&
          oma_exec "Hibernation removed" omarchy hibernation remove
      else
        oma_dim "Hibernation is not set up. This resizes swap and needs sudo."
        printf '\n'
        oma_confirm "Set up hibernation now?" &&
          oma_exec "Hibernation configured" omarchy hibernation setup
      fi
      ;;
    suspend)
      printf '\n'
      oma_spin "Suspend availability toggled" omarchy toggle suspend
      sleep 0.6
      ;;
    back | *) return 0 ;;
    esac
  done
}
