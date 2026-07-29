#!/bin/bash
# Default applications. `omarchy default <kind>` with no argument reports the
# current selection, which is what fills the value column here.

_defaults_set() {
  local kind="$1" label="$2"
  shift 2

  local current choice
  current=$(omarchy default "$kind" 2>/dev/null)
  choice=$(oma_pick "$label — current: ${current:-none}" "$current" "$@") || return 0
  [[ -z $choice || $choice == "$current" ]] && return 0

  printf '\n'
  if ! oma_spin "Default $kind set to $choice" omarchy default "$kind" "$choice"; then
    oma_dim "If it is not installed yet, try: omarchy install $kind $choice"
    oma_pause
    return 1
  fi
  sleep 0.4
}

defaults_menu() {
  while true; do
    oma_screen "Default Apps"

    local choice
    choice=$(oma_select "Applications Omarchy opens for you" \
      "$(printf 'browser\tBrowser\t%s' "$(omarchy default browser 2>/dev/null)")" \
      "$(printf 'editor\tEditor\t%s' "$(omarchy default editor 2>/dev/null)")" \
      "$(printf 'terminal\tTerminal\t%s' "$(omarchy default terminal 2>/dev/null)")" \
      "$OMA_BACK") || return 0

    case "$choice" in
    browser) _defaults_set browser "Default browser" chromium chrome brave brave-origin edge firefox zen ;;
    editor) _defaults_set editor "Default editor" code cursor zed sublime_text helix vim emacs nvim ;;
    terminal) _defaults_set terminal "Default terminal" alacritty foot ghostty kitty ;;
    back | *) return 0 ;;
    esac
  done
}
