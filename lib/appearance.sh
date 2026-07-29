#!/bin/bash
# Appearance: theme, font, wallpaper, and window decoration.

_appearance_theme() {
  local -a themes=()
  mapfile -t themes < <(omarchy theme list 2>/dev/null)
  ((${#themes[@]})) || {
    oma_err "could not list themes"
    oma_pause
    return 1
  }

  local current choice
  current=$(omarchy theme current 2>/dev/null)
  choice=$(oma_pick "Theme — current: ${current:-unknown}" "$current" "${themes[@]}") || return 0
  [[ -z $choice || $choice == "$current" ]] && return 0

  printf '\n'
  oma_spin "Applied theme: $choice" omarchy theme set "$choice"
  # The new palette should drive the rest of this session.
  oma_load_theme
  sleep 0.4
}

_appearance_font() {
  local -a fonts=()
  mapfile -t fonts < <(omarchy font list 2>/dev/null)
  ((${#fonts[@]})) || {
    oma_err "could not list fonts"
    oma_pause
    return 1
  }

  local current choice
  current=$(omarchy font current 2>/dev/null)
  choice=$(oma_pick "Monospace font — current: ${current:-unknown}" "$current" "${fonts[@]}") || return 0
  [[ -z $choice || $choice == "$current" ]] && return 0

  printf '\n'
  oma_spin "Applied font: $choice" omarchy font set "$choice"
  sleep 0.4
}

_appearance_background() {
  while true; do
    oma_screen "Appearance › Wallpaper"
    local link current
    link=$(readlink -f "$HOME/.config/omarchy/current/background" 2>/dev/null)
    current=$(basename "${link:-none}")

    local choice
    choice=$(oma_select "Wallpaper — $current" \
      $'next\tCycle to next wallpaper\t' \
      $'pick\tPick from this theme\t' \
      $'folder\tOpen wallpaper folder\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    next)
      printf '\n'
      oma_spin "Next wallpaper" omarchy theme bg next
      sleep 0.4
      ;;
    pick)
      local dir="$HOME/.config/omarchy/current/theme/backgrounds"
      [[ -d $dir ]] || {
        oma_err "no backgrounds directory for this theme"
        oma_pause
        continue
      }
      local file
      file=$(gum file "$dir" --header "Pick a wallpaper" --height 15) || continue
      printf '\n'
      oma_spin "Wallpaper set" omarchy theme bg set "$file"
      sleep 0.4
      ;;
    folder)
      omarchy theme bg install >/dev/null 2>&1 &
      oma_ok "opened the wallpaper folder"
      sleep 0.6
      ;;
    back | *) return 0 ;;
    esac
  done
}

_appearance_bg_name() {
  basename "$(readlink -f "$HOME/.config/omarchy/current/background" 2>/dev/null)" 2>/dev/null
}

appearance_menu() {
  while true; do
    oma_screen "Appearance"

    local -a entries=()
    entries+=("$(printf 'theme\tTheme\t%s' "$(omarchy theme current 2>/dev/null)")")
    entries+=("$(printf 'font\tMonospace font\t%s' "$(omarchy font current 2>/dev/null)")")
    entries+=("$(printf 'bg\tWallpaper\t%s' "$(_appearance_bg_name)")")
    mapfile -t -O "${#entries[@]}" entries < <(oma_reg_entries appearance)
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Theme, font, and window decoration" "${entries[@]}") || return 0

    case "$choice" in
    theme) _appearance_theme ;;
    font) _appearance_font ;;
    bg) _appearance_background ;;
    reg:*) oma_reg_edit "${choice#reg:}" ;;
    back | *) return 0 ;;
    esac
  done
}
