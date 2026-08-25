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

# Omarchy 4 keeps idle timeouts in shell.json as seconds since the user went
# idle; Omarchy 3 had a separate hypridle daemon with its own config file.

_idle_secs_label() {
  local s="$1"
  [[ $s =~ ^[0-9]+$ ]] || {
    printf 'default'
    return
  }
  ((s == 0)) && {
    printf 'never'
    return
  }
  if ((s % 60 == 0)); then printf '%d min' "$((s / 60))"; else printf '%ds' "$s"; fi
}

# Ask for a timeout in minutes and store it as seconds. 0 disables the timer.
_idle_edit() {
  local key="$1" label="$2"
  local cur mins
  cur=$(shell_get ".idle.$key")

  local cur_mins=""
  [[ $cur =~ ^[0-9]+$ ]] && cur_mins=$((cur / 60))

  mins=$(gum input --header "$label after how many minutes? (0 = never)" \
    --value "$cur_mins" --placeholder "5") || return 0
  mins="${mins//$'\n'/}"
  [[ -z $mins ]] && return 0
  [[ $mins =~ ^[0-9]+$ ]] || {
    oma_err "expected a whole number of minutes"
    oma_pause
    return 1
  }

  oma_backup "$OMA_SHELL_JSON"
  shell_set ".idle.$key" "$((mins * 60))" || {
    oma_err "could not write $OMA_SHELL_JSON"
    oma_pause
    return 1
  }
  oma_ok "$label after $(_idle_secs_label "$((mins * 60))")"
  # shell.json hot-reloads, so there is nothing to restart.
  sleep 0.5
}

_power_idle_shell() {
  while true; do
    oma_screen "Power › Idle & lock"

    # `omarchy toggle idle` parks the system in stay-awake; the timers below
    # are what it suspends.
    local awake="normal"
    [[ -f "$OMA_STATE_DIR/indicators/stay-awake" ]] && awake="staying awake"

    local choice
    choice=$(oma_select "When the screen locks and blanks while you are away" \
      "$(printf 'toggle\tIdle behaviour\t%s' "$awake")" \
      "$(printf 'lock\tLock the screen\t%s' "$(_idle_secs_label "$(shell_get '.idle.lock')")")" \
      "$(printf 'screensaver\tStart the screensaver\t%s' "$(_idle_secs_label "$(shell_get '.idle.screensaver')")")" \
      $'edit\tEdit shell.json directly\t' \
      $'reset\tReset the shell config to defaults\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    toggle)
      printf '\n'
      oma_spin "Idle behaviour toggled" omarchy toggle idle
      sleep 0.6
      ;;
    lock) _idle_edit lock "Lock the screen" ;;
    screensaver) _idle_edit screensaver "Start the screensaver" ;;
    edit) oma_edit_file "$OMA_SHELL_JSON" && sleep 0.2 ;;
    reset)
      oma_confirm "Reset shell.json to the Omarchy default?" &&
        oma_exec "Shell config reset" omarchy refresh shell
      ;;
    back | *) return 0 ;;
    esac
  done
}

_power_idle_hypridle() {
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

_power_idle() {
  if oma_v4; then _power_idle_shell; else _power_idle_hypridle; fi
}

# Battery percentage straight from sysfs — the one source both Omarchy
# generations agree on, and the only one Omarchy 4 still reports per-value.
_power_battery_pct() {
  local b
  for b in /sys/class/power_supply/BAT*/capacity; do
    [[ -r $b ]] && {
      printf '%s%%' "$(<"$b")"
      return
    }
  done
}

power_menu() {
  while true; do
    oma_screen "Power"

    local profile="" battery=""
    oma_has powerprofilesctl && profile=$(powerprofilesctl get 2>/dev/null)
    # `omarchy battery status` is a long glyph-laden string built for the bar;
    # the menu column only has room for the percentage.
    omarchy battery present >/dev/null 2>&1 && battery=$(_power_battery_pct)

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
        # Omarchy 4 dropped the individual battery readouts in favour of one
        # formatted status line; Omarchy 3 can still be asked for the parts.
        if oma_v4; then
          oma_dim "Charge:    $(_power_battery_pct)"
          oma_dim "Status:    $(omarchy battery status 2>/dev/null)"
        else
          oma_dim "Charge:    $(omarchy battery remaining 2>/dev/null)%"
          oma_dim "Status:    $(omarchy battery status 2>/dev/null)"
          oma_dim "Remaining: $(omarchy battery remaining time 2>/dev/null)"
          oma_dim "Capacity:  $(omarchy battery capacity 2>/dev/null) Wh"
        fi
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
