#!/bin/bash
# Network: Wi-Fi, Bluetooth, and DNS.
#
# Connecting to networks is handled by what Omarchy already ships — TUIs on
# Omarchy 3, shell panels on 4 — so this section covers status and the settings
# that live outside them.

_net_wifi_iface() {
  local p
  for p in /sys/class/net/*/wireless; do
    [[ -e $p ]] || continue
    basename "$(dirname "$p")"
    return
  done
}

_net_wifi_powersave() {
  local iface
  iface=$(_net_wifi_iface)
  [[ -z $iface ]] && return 0
  oma_has iw || return 0
  iw dev "$iface" get power_save 2>/dev/null | grep -oE 'on|off' | head -1
}

# The active NetworkManager connection, which is where a persistent powersave
# setting has to be written.
_net_active_con() {
  oma_has nmcli || return 0
  nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
    awk -F: '$2 ~ /wireless/ { print $1; exit }'
}

# Omarchy 4 removed `omarchy wifi powersave`, so set it through NetworkManager
# directly: 3 enables powersave for the connection, 2 disables it.
_net_set_powersave() {
  local want="$1" con
  con=$(_net_active_con)
  [[ -z $con ]] && {
    oma_err "no active Wi-Fi connection to configure"
    oma_pause
    return 1
  }
  local val=2
  [[ $want == on ]] && val=3

  oma_spin "Wi-Fi power saving $want for \"$con\"" \
    nmcli connection modify "$con" 802-11-wireless.powersave "$val" || return 1
  # The change lands on the next activation; bounce the connection so the menu
  # and the radio agree straight away.
  oma_spin "Reconnected" nmcli connection up "$con"
}

_net_wifi_status() {
  local iface
  iface=$(_net_wifi_iface)
  [[ -z $iface ]] && {
    printf 'no wireless device'
    return
  }
  local ssid
  ssid=$(iw dev "$iface" link 2>/dev/null | sed -n 's/.*SSID: //p' | head -1)
  [[ -n $ssid ]] && printf '%s' "$ssid" || printf 'not connected'
}

# bluez-utils (bluetoothctl) is optional on Omarchy — bluetui is the shipped
# front end — so fall back to the service and rfkill state when it is absent.
_net_bt_status() {
  if oma_has bluetoothctl; then
    local powered connected
    powered=$(bluetoothctl show 2>/dev/null | sed -n 's/.*Powered: //p' | head -1)
    if [[ -n $powered ]]; then
      connected=$(bluetoothctl devices Connected 2>/dev/null | grep -c .)
      if [[ $powered == yes ]]; then
        ((connected > 0)) && printf 'on · %s connected' "$connected" || printf 'on'
      else
        printf 'off'
      fi
      return
    fi
  fi

  systemctl is-active bluetooth >/dev/null 2>&1 || {
    printf 'service stopped'
    return
  }
  if oma_has rfkill && rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes'; then
    printf 'blocked'
    return
  fi
  printf 'on'
}

network_menu() {
  while true; do
    oma_screen "Network"

    local choice
    choice=$(oma_select "Wi-Fi, Bluetooth, and DNS" \
      "$(printf 'wifi\tWi-Fi\t%s' "$(_net_wifi_status)")" \
      "$(printf 'bt\tBluetooth\t%s' "$(_net_bt_status)")" \
      "$(printf 'powersave\tWi-Fi power saving\t%s' "$(_net_wifi_powersave)")" \
      "$(printf 'dns\tDNS provider\t%s' "$(oma_v4 && omarchy dns 2>/dev/null)")" \
      $'restartwifi\tRestart Wi-Fi\t' \
      $'restartbt\tRestart Bluetooth\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    wifi)
      # shellcheck disable=SC2046  # the mapped command is split on purpose
      $(oma_cmd_line wifi-menu) >/dev/null 2>&1 &
      oma_ok "opened the Wi-Fi controls"
      sleep 0.6
      ;;
    bt)
      # shellcheck disable=SC2046
      $(oma_cmd_line bt-menu) >/dev/null 2>&1 &
      oma_ok "opened the Bluetooth controls"
      sleep 0.6
      ;;
    powersave)
      local iface
      iface=$(_net_wifi_iface)
      [[ -z $iface ]] && {
        oma_err "no wireless interface found"
        oma_pause
        continue
      }
      local cur pick
      cur=$(_net_wifi_powersave)
      pick=$(oma_pick "Wi-Fi power saving on $iface — saves battery, can add latency" \
        "$cur" on off) || continue
      [[ -z $pick || $pick == "$cur" ]] && continue
      printf '\n'
      if oma_v4; then
        _net_set_powersave "$pick"
      else
        oma_spin "Wi-Fi power saving $pick" omarchy wifi powersave "$pick"
      fi
      sleep 0.4
      ;;
    dns)
      if oma_v4; then
        # Omarchy 4 takes the provider as an argument instead of prompting.
        local cur_dns pick_dns
        cur_dns=$(omarchy dns 2>/dev/null)
        pick_dns=$(oma_pick "DNS provider — current: ${cur_dns:-unknown}" "$cur_dns" \
          Cloudflare Google DHCP Custom) || continue
        [[ -z $pick_dns ]] && continue
        oma_exec "DNS set to $pick_dns" omarchy dns "$pick_dns"
      else
        oma_exec "DNS configured" omarchy setup dns
      fi
      ;;
    restartwifi) oma_exec "Wi-Fi restarted" omarchy restart wifi ;;
    restartbt) oma_exec "Bluetooth restarted" omarchy restart bluetooth ;;
    back | *) return 0 ;;
    esac
  done
}
