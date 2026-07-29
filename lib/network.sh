#!/bin/bash
# Network: Wi-Fi, Bluetooth, and DNS.
#
# Connecting to networks is handled by the TUIs Omarchy already ships (impala
# for Wi-Fi, bluetui for Bluetooth); this section covers status and the
# settings that live outside them.

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
      $'dns\tDNS provider\t' \
      $'restartwifi\tRestart Wi-Fi\t' \
      $'restartbt\tRestart Bluetooth\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    wifi)
      omarchy launch wifi >/dev/null 2>&1 &
      oma_ok "opened the Wi-Fi controls"
      sleep 0.6
      ;;
    bt)
      omarchy launch bluetooth >/dev/null 2>&1 &
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
      oma_spin "Wi-Fi power saving $pick" omarchy wifi powersave "$pick"
      sleep 0.4
      ;;
    dns) oma_exec "DNS configured" omarchy setup dns ;;
    restartwifi) oma_exec "Wi-Fi restarted" omarchy restart wifi ;;
    restartbt) oma_exec "Bluetooth restarted" omarchy restart bluetooth ;;
    back | *) return 0 ;;
    esac
  done
}
