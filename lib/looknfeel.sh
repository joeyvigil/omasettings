#!/bin/bash
# Look & feel: tiling geometry, borders, layout, and animations.

# Omarchy's no-gaps mode pins gaps, borders, and rounding to 0 from a file
# sourced after ~/.config/hypr, so it overrides everything below it.
_lnf_gaps_mode() {
  [[ -f "$OMA_STATE_DIR/toggles/hypr/window-no-gaps.conf" ]] &&
    printf 'no gaps (overrides the settings below)' || printf 'default'
}

looknfeel_menu() {
  local LNF="$OMA_LOOKNFEEL"
  while true; do
    oma_screen "Look & Feel"

    local -a entries=()
    entries+=("$(printf 'nogaps\tWindow gaps mode\t%s' "$(_lnf_gaps_mode)")")
    mapfile -t -O "${#entries[@]}" entries < <(oma_reg_entries looknfeel)
    entries+=($'edit\tEdit looknfeel.conf directly\t')
    entries+=($'reset\tReset Hyprland config to defaults\t')
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Gaps, borders, layout, and animations" "${entries[@]}") || return 0

    case "$choice" in
    nogaps)
      printf '\n'
      oma_spin "Window gaps mode toggled" omarchy hyprland window gaps toggle
      sleep 0.6
      ;;
    reg:*) oma_reg_edit "${choice#reg:}" ;;
    edit)
      oma_edit_file "$LNF" && hypr_apply "$LNF"
      sleep 0.4
      ;;
    reset)
      oma_screen "Look & Feel › Reset"
      oma_warn "This overwrites every file in ~/.config/hypr with Omarchy's defaults."
      oma_dim "Omarchy backs up the current files first."
      printf '\n'
      oma_confirm "Reset all Hyprland config to defaults?" &&
        oma_exec "Hyprland config reset" omarchy refresh hyprland
      ;;
    back | *) return 0 ;;
    esac
  done
}
