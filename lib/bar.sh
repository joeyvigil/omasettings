#!/bin/bash
# The Omarchy 4 status bar: which widgets appear, where they sit, and how the
# bar itself is drawn.
#
# Omarchy 4 replaced Waybar with a bar rendered by the Quickshell-based Omarchy
# shell. Widgets are plugins: `omarchy plugin list` enumerates them and
# enable/disable decides whether they exist at all, while `omarchy bar` places
# them. Both write shell.json, which the shell hot-reloads, so nothing here
# needs a restart. Waybar's equivalent for Omarchy 3 lives in waybar.sh.

# Every bar widget, as "id<TAB>name<TAB>enabled".
_bar_widgets() {
  omarchy plugin list --json 2>/dev/null | jq -r '
    .[]
    | select(.kinds | index("bar-widget"))
    | "\(.id)\t\(.name)\t\(.enabled)"' 2>/dev/null
}

# A widget can be enabled as a plugin but not placed on the bar, so the column
# shows the section when it has one and the plugin state otherwise.
_bar_widget_state() {
  local id="$1" enabled="$2" section
  section=$(shell_bar_section_of "$id")
  if [[ $section != off ]]; then
    printf '%s' "$section"
  elif [[ $enabled == true ]]; then
    printf 'enabled, not placed'
  else
    printf 'off'
  fi
}

_bar_widget_menu() {
  local id="$1" name="$2"

  while true; do
    oma_screen "Bar › $name"

    local section
    section=$(shell_bar_section_of "$id")
    oma_dim "$id"
    printf '\n'

    local choice
    choice=$(oma_select "$name — currently ${section}" \
      $'left\tMove to left\t' \
      $'center\tMove to center\t' \
      $'right\tMove to right\t' \
      $'off\tRemove from the bar\t' \
      "$OMA_BACK") || return 0
    [[ $choice == back ]] && return 0
    [[ $choice == "$section" ]] && continue

    printf '\n'
    if [[ $choice == off ]]; then
      oma_spin "$name removed from the bar" omarchy plugin disable "$id"
    elif [[ $section == off ]]; then
      # Not on the bar at all: enabling places it, then move it where asked.
      oma_spin "$name added to $choice" omarchy plugin enable "$id" --section "$choice"
    else
      oma_spin "$name moved to $choice" omarchy bar move "$id" --section "$choice"
    fi
    sleep 0.5
    return 0
  done
}

_bar_widgets_menu() {
  while true; do
    oma_screen "Bar › Widgets"

    local -a entries=()
    local id name enabled
    while IFS=$'\t' read -r id name enabled; do
      [[ -z $id ]] && continue
      entries+=("$(printf 'w:%s\t%s\t%s' "$id" "$name" "$(_bar_widget_state "$id" "$enabled")")")
    done < <(_bar_widgets)

    ((${#entries[@]})) || {
      oma_err "could not list bar widgets"
      oma_dim "Is the Omarchy shell running? Try: omarchy restart shell"
      oma_pause
      return 1
    }
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Where each widget sits in the bar" "${entries[@]}") || return 0
    [[ $choice == back ]] && return 0

    local wid="${choice#w:}" wname
    wname=$(_bar_widgets | awk -F'\t' -v i="$wid" '$1 == i { print $2; exit }')
    _bar_widget_menu "$wid" "${wname:-$wid}"
  done
}

_bar_v4_menu() {
  while true; do
    oma_screen "Bar"

    if ! shell_json_ok; then
      oma_err "cannot parse $OMA_SHELL_JSON"
      oma_dim "Fix it by hand, or reset it below."
      printf '\n'
      local c
      c=$(oma_select "Bar" \
        $'edit\tEdit shell.json\t' \
        $'reset\tReset the shell config to defaults\t' \
        "$OMA_BACK") || return 0
      case "$c" in
      edit) oma_edit_file "$OMA_SHELL_JSON" ;;
      reset)
        oma_confirm "Reset shell.json to the Omarchy default?" &&
          oma_exec "Shell config reset" omarchy refresh shell
        ;;
      *) return 0 ;;
      esac
      continue
    fi

    # The bar is hidden with a flag file, independently of whether the shell
    # that draws it is running, so both are worth showing.
    local placed visible
    placed=$(shell_bar_placements | grep -c .)
    visible=$(_toggle_flag_state bar-off)
    pgrep -x quickshell >/dev/null 2>&1 || visible+=" (shell stopped)"

    local choice
    choice=$(oma_select "Bar layout and appearance" \
      "$(printf 'visible\tBar visibility\t%s' "$visible")" \
      "$(printf 'widgets\tWidgets…\t%s placed' "$placed")" \
      "$(printf 'position\tBar position\t%s' "$(shell_get '.bar.position' top)")" \
      "$(printf 'transparent\tTransparent bar\t%s' "$(shell_get '.bar.transparent' false)")" \
      $'defaults\tRestore the default widget layout\t' \
      $'edit\tEdit shell.json directly\t' \
      $'restart\tRestart the Omarchy shell\t' \
      $'reset\tReset the shell config to defaults\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    visible)
      printf '\n'
      oma_spin "Bar toggled" omarchy toggle bar
      sleep 0.6
      ;;
    widgets) _bar_widgets_menu ;;
    position)
      local p
      p=$(oma_pick "Bar position" "$(shell_get '.bar.position' top)" \
        top bottom left right) || continue
      [[ -z $p ]] && continue
      printf '\n'
      oma_spin "Bar position: $p" omarchy bar position "$p"
      sleep 0.4
      ;;
    transparent)
      printf '\n'
      oma_spin "Bar transparency toggled" omarchy bar transparent toggle
      sleep 0.4
      ;;
    defaults)
      oma_confirm "Restore the default bar and widget layout?" && {
        printf '\n'
        oma_spin "Default bar layout restored" omarchy bar defaults
        sleep 0.5
      }
      ;;
    edit) oma_edit_file "$OMA_SHELL_JSON" && sleep 0.2 ;;
    restart)
      printf '\n'
      shell_restart
      sleep 0.4
      ;;
    reset)
      oma_confirm "Reset shell.json to the Omarchy default?" &&
        oma_exec "Shell config reset" omarchy refresh shell
      ;;
    back | *) return 0 ;;
    esac
  done
}

# The section is called "Waybar" on Omarchy 3 and just "Bar" on 4, where the
# bar is drawn by the Omarchy shell rather than a separate program.
oma_bar_label() { oma_v4 && printf 'Bar' || printf 'Waybar'; }

bar_menu() {
  if oma_v4; then _bar_v4_menu; else waybar_menu; fi
}
