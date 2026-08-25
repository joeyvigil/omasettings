#!/bin/bash
# Appearance: theme, font, wallpaper, and window decoration.

# --- theme previews ----------------------------------------------------------

# `omarchy theme list` prints display names ("Tokyo Night"); directories are
# slugs ("tokyo-night"). This is the same transform omarchy-theme-set applies.
_theme_slug() {
  printf '%s' "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# User themes shadow stock ones of the same slug, so ~/.config wins the lookup.
# $OMARCHY_PATH is where Omarchy 4 keeps the stock themes; Omarchy 3 kept them
# under ~/.local/share, which Omarchy 4 leaves as a symlink to the same place.
_theme_bases() {
  printf '%s\n' "$HOME/.config/omarchy/themes" \
    "$OMARCHY_PATH/themes" "$HOME/.local/share/omarchy/themes"
}

_theme_dir() {
  local slug base
  slug=$(_theme_slug "$1")
  while IFS= read -r base; do
    [[ -d "$base/$slug" ]] && {
      printf '%s' "$base/$slug"
      return 0
    }
  done < <(_theme_bases)
  return 1
}

# A user theme can shadow a stock one without carrying its own screenshot, so
# check both locations rather than only the directory that won the lookup.
_theme_file() {
  local slug base f
  slug=$(_theme_slug "$1")
  while IFS= read -r base; do
    f="$base/$slug/$2"
    [[ -f $f ]] && {
      printf '%s' "$f"
      return 0
    }
  done < <(_theme_bases)
  return 1
}

_theme_swatch() {
  local hex="${1#\#}"
  [[ ${#hex} == 6 && $hex =~ ^[0-9a-fA-F]+$ ]] || return 0
  printf '\033[48;2;%d;%d;%dm    \033[0m' \
    "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

_theme_palette() {
  local colors="$1/colors.toml"
  [[ -f $colors ]] || return 0

  local i hex
  printf '  '
  for i in {0..7}; do _theme_swatch "$(_oma_toml "$colors" "color$i")"; done
  printf '\n  '
  for i in {8..15}; do _theme_swatch "$(_oma_toml "$colors" "color$i")"; done
  printf '\n\n'

  local bg fg accent
  bg=$(_oma_toml "$colors" background)
  fg=$(_oma_toml "$colors" foreground)
  accent=$(_oma_toml "$colors" accent)
  printf '  bg %-9s  fg %-9s  accent %s\n' "$bg" "$fg" "$accent"
}

# chafa auto-detects the terminal, but graphics protocols do not clip to fzf's
# preview pane — they draw over the whole window. Unicode blocks always land in
# the right place, and are the only option in Alacritty anyway.
_theme_image() {
  local img="$1" cols="$2" rows="$3"
  ((rows < 3)) && rows=3

  if oma_has chafa; then
    chafa --format=symbols --colors=full --animate=off \
      --size="${cols}x${rows}" "$img" 2>/dev/null && return 0
  fi

  printf '  Install chafa to see the theme screenshot here:\n'
  printf '      omarchy pkg add chafa\n'
  return 0
}

# Rendered into fzf's preview pane, once per highlighted theme.
theme_preview() {
  local name="$1" dir img
  dir=$(_theme_dir "$name") || {
    printf '  Theme "%s" not found.\n' "$name"
    return 0
  }

  local cols=${FZF_PREVIEW_COLUMNS:-56} lines=${FZF_PREVIEW_LINES:-20}
  printf '\n  \033[1m%s\033[0m\n\n' "$name"

  if img=$(_theme_file "$name" preview.png); then
    _theme_image "$img" "$((cols - 2))" "$((lines - 9))"
  else
    printf '  (this theme ships no preview.png)\n'
  fi

  printf '\n'
  _theme_palette "$dir"
}

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

  # fzf is the only picker here that can show a live preview beside the list.
  local rc=0
  if oma_has fzf && [[ -n ${OMA_SELF:-} ]]; then
    clear
    choice=$(printf '%s\n' "${themes[@]}" | fzf \
      --layout=reverse --height=100% --info=inline \
      --prompt="  " --pointer="❯" --marker="●" \
      --header="Theme — current: ${current:-unknown}" \
      --preview="\"$OMA_SELF\" __theme-preview {}" \
      --preview-window="right,58%,border-left" \
      --color="fg:$OMA_FG,fg+:$OMA_ACCENT,hl:$OMA_ACCENT,hl+:$OMA_ACCENT,pointer:$OMA_ACCENT,marker:$OMA_ACCENT,prompt:$OMA_ACCENT,header:$OMA_DIM,info:$OMA_DIM,border:$OMA_ACCENT,gutter:-1") || rc=$?

    # 130 is esc/ctrl-c and 1 is "no match" — both mean the user is done. Any
    # other non-zero code is fzf itself failing (no usable tty, bad terminal),
    # so fall through to the plain picker instead of dead-ending on it.
    case $rc in
    0) ;;
    1 | 130) return 0 ;;
    *) choice=$(oma_pick "Theme — current: ${current:-unknown}" "$current" "${themes[@]}") || return 0 ;;
    esac
  else
    choice=$(oma_pick "Theme — current: ${current:-unknown}" "$current" "${themes[@]}") || return 0
  fi
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
    link=$(readlink -f "$OMA_BACKGROUND" 2>/dev/null)
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
      local dir="$OMA_THEME_DIR/backgrounds"
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
  basename "$(readlink -f "$OMA_BACKGROUND" 2>/dev/null)" 2>/dev/null
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
