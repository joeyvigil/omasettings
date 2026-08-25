#!/bin/bash
# Keybindings on Omarchy 3: browse, search, rebind, add, and remove.
#
# Omarchy 4 declares bindings in Lua, where this file's approach does not
# apply at all; keybindings4.sh handles that generation, and keybindings_menu
# at the bottom picks between them.
#
# Bindings are read from `hyprctl binds` rather than the config files, so what
# you see is what Hyprland is actually running — Omarchy defaults included.
# Note that `hyprctl -j binds` emits malformed JSON in current Hyprland (keys
# and values come out misaligned), hence the plain-text parser below.

# OMA_BINDINGS is resolved by compat.sh (bindings.conf on 3, bindings.lua on 4).

# Hyprland modmask bits.
_kb_mods() {
  local m="$1" out=""
  ((m & 64)) && out+="SUPER "
  ((m & 4)) && out+="CTRL "
  ((m & 8)) && out+="ALT "
  ((m & 1)) && out+="SHIFT "
  printf '%s' "${out% }"
}

# Emits: modmask <US> key <US> description <US> dispatcher <US> arg
_kb_raw() {
  oma_hypr_live || return 1
  hyprctl binds 2>/dev/null | awk '
    BEGIN { RS = ""; FS = "\n"; US = sprintf("%c", 31) }
    {
      mod = ""; key = ""; desc = ""; disp = ""; arg = ""
      for (i = 1; i <= NF; i++) {
        line = $i
        sub(/^[[:space:]]+/, "", line)
        if (line ~ /^modmask: /)          mod  = substr(line, 10)
        else if (line ~ /^key: /)         key  = substr(line, 6)
        else if (line ~ /^description: /) desc = substr(line, 14)
        else if (line ~ /^dispatcher: /)  disp = substr(line, 13)
        else if (line ~ /^arg: /)         arg  = substr(line, 6)
      }
      if (key != "") print mod US key US desc US disp US arg
    }
  '
}

# Display lines: "SUPER + K    Description    dispatcher arg"
_kb_lines() {
  local mod key desc disp arg combo action
  while IFS=$'\x1f' read -r mod key desc disp arg; do
    combo=$(_kb_mods "$mod")
    [[ -n $combo ]] && combo+=" + $key" || combo="$key"
    action="$desc"
    [[ -z $action ]] && action="$disp${arg:+ $arg}"
    printf '%-34s %s\n' "$combo" "$action"
  done < <(_kb_raw)
}

_kb_browse() {
  local -a lines=()
  mapfile -t lines < <(_kb_lines | sort)
  ((${#lines[@]})) || {
    oma_err "could not read bindings (is Hyprland running?)"
    oma_pause
    return 1
  }

  local pick
  pick=$(printf '%s\n' "${lines[@]}" |
    gum filter --header "${#lines[@]} bindings — type to search, enter for details" \
      --height 20 --placeholder "e.g. screenshot, SUPER SHIFT, workspace" \
      --indicator "❯" --prompt "  ") || return 0
  [[ -z $pick ]] && return 0

  # Recover the full record for the chosen line.
  local combo="${pick%%  *}"
  combo="${combo%"${combo##*[![:space:]]}"}"
  local mod key desc disp arg c
  while IFS=$'\x1f' read -r mod key desc disp arg; do
    c=$(_kb_mods "$mod")
    [[ -n $c ]] && c+=" + $key" || c="$key"
    [[ $c == "$combo" ]] && break
  done < <(_kb_raw)

  oma_screen "Keybindings › Detail"
  oma_dim "Combo:      $combo"
  [[ -n $desc ]] && oma_dim "Action:     $desc"
  oma_dim "Dispatcher: $disp"
  [[ -n $arg ]] && oma_dim "Argument:   $arg"
  printf '\n'

  local choice
  choice=$(oma_select "This binding" \
    $'rebind\tMove it to a different key\t' \
    $'copy\tShow the config line for it\t' \
    "$OMA_BACK") || return 0

  case "$choice" in
  rebind) _kb_rebind "$combo" "$desc" "$disp" "$arg" ;;
  copy)
    oma_screen "Keybindings › Config line"
    local line
    if [[ -n $desc ]]; then
      line="bindd = ${combo/ + /, }, $desc, $disp${arg:+, $arg}"
    else
      line="bind = ${combo/ + /, }, $disp${arg:+, $arg}"
    fi
    printf '\n'
    gum style --border rounded --border-foreground "$OMA_ACCENT" --padding "0 1" "$line"
    printf '\n'
    oma_dim "Paste that into ~/.config/hypr/bindings.conf to customize it."
    oma_pause
    ;;
  esac
}

# Ask for a combo like "SUPER SHIFT, K" and normalize it.
_kb_ask_combo() {
  local prompt="$1" value
  value=$(gum input --header "$prompt" \
    --placeholder "SUPER SHIFT, K" --value "${2:-}") || return 1
  value="${value//$'\n'/}"
  [[ -z $value ]] && return 1

  # Accept both "SUPER SHIFT + K" and "SUPER SHIFT, K".
  value="${value/ + /, }"
  [[ $value == *,* ]] || {
    oma_err "expected modifiers and a key, e.g. \"SUPER SHIFT, K\""
    oma_pause
    return 1
  }
  printf '%s' "$value"
}

# Rebinding means unbinding the old combo and binding the action to a new one.
# Hyprland needs an explicit `unbind` before an override, and bindings.conf is
# sourced after Omarchy's defaults, so both lines belong there.
_kb_rebind() {
  local old_combo="$1" desc="$2" disp="$3" arg="$4"
  local old="${old_combo/ + /, }"

  local new
  new=$(_kb_ask_combo "New combo for \"${desc:-$disp}\" (currently $old_combo)") || return 0
  [[ $new == "$old" ]] && return 0

  # Warn if the target combo is already taken.
  local conflict
  conflict=$(_kb_lines | awk -v c="${new/, / + }" -F'  +' '$1 == c { print $2; exit }')

  oma_screen "Keybindings › Rebind"
  oma_dim "Action:  ${desc:-$disp $arg}"
  oma_dim "From:    $old_combo"
  oma_dim "To:      ${new/, / + }"
  [[ -n $conflict ]] && {
    printf '\n'
    oma_warn "${new/, / + } is already bound to: $conflict"
    oma_dim "It will be unbound so the new binding wins."
  }
  printf '\n'
  oma_confirm "Write this to bindings.conf?" || return 0

  oma_backup "$OMA_BINDINGS"
  {
    printf '\n# Rebound by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'unbind = %s\n' "$old"
    [[ -n $conflict ]] && printf 'unbind = %s\n' "$new"
    if [[ -n $desc ]]; then
      printf 'bindd = %s, %s, %s%s\n' "$new" "$desc" "$disp" "${arg:+, $arg}"
    else
      printf 'bind = %s, %s%s\n' "$new" "$disp" "${arg:+, $arg}"
    fi
  } >>"$OMA_BINDINGS"

  oma_ok "rebound to ${new/, / + }"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

_kb_add() {
  oma_screen "Keybindings › Add"

  local combo
  combo=$(_kb_ask_combo "Key combo for the new binding") || return 0

  local cmd
  cmd=$(gum input --header "Command to run" \
    --placeholder "uwsm-app -- alacritty") || return 0
  [[ -z $cmd ]] && return 0

  local desc
  desc=$(gum input --header "Short description (shown in the keybindings menu)" \
    --placeholder "My terminal") || return 0

  local conflict
  conflict=$(_kb_lines | awk -v c="${combo/, / + }" -F'  +' '$1 == c { print $2; exit }')

  oma_screen "Keybindings › Add"
  oma_dim "Combo:   ${combo/, / + }"
  oma_dim "Command: $cmd"
  [[ -n $conflict ]] && {
    printf '\n'
    oma_warn "${combo/, / + } is already bound to: $conflict"
    oma_dim "It will be unbound first."
  }
  printf '\n'
  oma_confirm "Add this binding?" || return 0

  oma_backup "$OMA_BINDINGS"
  {
    printf '\n# Added by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
    [[ -n $conflict ]] && printf 'unbind = %s\n' "$combo"
    if [[ -n $desc ]]; then
      printf 'bindd = %s, %s, exec, %s\n' "$combo" "$desc" "$cmd"
    else
      printf 'bind = %s, exec, %s\n' "$combo" "$cmd"
    fi
  } >>"$OMA_BINDINGS"

  oma_ok "added ${combo/, / + }"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

# Only bindings defined in the user's own file can be removed; the rest live in
# Omarchy's read-only defaults and must be overridden with `unbind` instead.
_kb_remove() {
  [[ -f $OMA_BINDINGS ]] || return 0

  local -a lines=()
  mapfile -t lines < <(grep -nE '^[[:space:]]*(bind|bindd|binde|bindl|bindm|unbind)[[:space:]]*=' \
    "$OMA_BINDINGS" | sed 's/\t/ /g')
  ((${#lines[@]})) || {
    oma_screen "Keybindings › Remove"
    oma_dim "No bindings defined in your bindings.conf yet."
    oma_pause
    return 0
  }

  local pick
  pick=$(printf '%s\n' "${lines[@]}" |
    gum filter --header "Your own bindings — pick one to delete" --height 18 \
      --indicator "❯" --prompt "  ") || return 0
  [[ -z $pick ]] && return 0

  local lineno="${pick%%:*}"
  oma_screen "Keybindings › Remove"
  oma_dim "${pick#*:}"
  printf '\n'
  oma_confirm "Delete line $lineno from bindings.conf?" || return 0

  oma_backup "$OMA_BINDINGS"
  sed -i "${lineno}d" "$OMA_BINDINGS"
  oma_ok "removed"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

# Hyprland fires every binding attached to a combo rather than picking one, so
# duplicates are often deliberate (Omarchy chains focus + raise on ALT+TAB).
# This lists them so you can tell intent from accident, not as an error report.
_kb_conflicts() {
  oma_screen "Keybindings › Shared combos"

  local -a dupes=()
  mapfile -t dupes < <(_kb_lines | awk -F'  +' '{ print $1 }' | sort | uniq -d)

  if ((${#dupes[@]} == 0)); then
    oma_ok "every combo is bound exactly once"
    oma_pause
    return 0
  fi

  oma_dim "${#dupes[@]} combo(s) run more than one action."
  oma_dim "Hyprland fires all of them; some of these are intentional."
  printf '\n'
  local c
  for c in "${dupes[@]}"; do
    _kb_lines | awk -F'  +' -v c="$c" '$1 == c { printf "    %-32s %s\n", $1, $2 }'
  done
  oma_pause
}

_keybindings_v3_menu() {
  while true; do
    oma_screen "Keybindings"

    local count
    count=$(_kb_raw | wc -l)

    local choice
    choice=$(oma_select "Browse and customize keyboard shortcuts" \
      "$(printf 'browse\tBrowse & search all bindings\t%s active' "$count")" \
      $'add\tAdd a new binding\t' \
      $'remove\tRemove one of your bindings\t' \
      $'conflicts\tCombos running more than one action\t' \
      $'edit\tEdit bindings.conf directly\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    browse) _kb_browse ;;
    add) _kb_add ;;
    remove) _kb_remove ;;
    conflicts) _kb_conflicts ;;
    edit)
      oma_edit_file "$OMA_BINDINGS" && hypr_apply "$OMA_BINDINGS"
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}

keybindings_menu() {
  if oma_v4; then _keybindings_v4_menu; else _keybindings_v3_menu; fi
}
