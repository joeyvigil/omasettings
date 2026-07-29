#!/bin/bash
# Input: keyboard, mouse, and touchpad behaviour.

_input_touchpad_menu() {
  local IN="$OMA_INPUT_CONF"
  while true; do
    oma_screen "Input › Touchpad"

    local hw_state="unknown"
    [[ -f "$OMA_STATE_DIR/toggles/hypr/touchpad-disabled.conf" ]] && hw_state="disabled" || hw_state="enabled"

    local -a entries=()
    entries+=("$(printf 'enabled\tTouchpad device\t%s' "$hw_state")")
    mapfile -t -O "${#entries[@]}" entries < <(oma_reg_entries touchpad)
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Touchpad" "${entries[@]}") || return 0

    case "$choice" in
    enabled)
      printf '\n'
      oma_spin "Touchpad toggled" omarchy toggle touchpad
      sleep 0.5
      ;;
    reg:*) oma_reg_edit "${choice#reg:}" ;;
    back | *) return 0 ;;
    esac
  done
}

input_menu() {
  local IN="$OMA_INPUT_CONF"
  while true; do
    oma_screen "Input"

    local -a entries=()
    mapfile -t entries < <(oma_reg_entries input)
    entries+=($'touchpad\tTouchpad…\t')
    entries+=($'touchscreen\tTouchscreen\t')
    entries+=($'edit\tEdit input.conf directly\t')
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Keyboard, mouse, and touchpad" "${entries[@]}") || return 0

    case "$choice" in
    reg:*) oma_reg_edit "${choice#reg:}" ;;
    touchpad) _input_touchpad_menu ;;
    touchscreen)
      printf '\n'
      oma_spin "Touchscreen toggled" omarchy toggle touchscreen
      sleep 0.5
      ;;
    edit)
      oma_edit_file "$IN" && hypr_apply "$IN"
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}
