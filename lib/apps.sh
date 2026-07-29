#!/bin/bash
# Apps & Startup: default applications, login startup programs, web apps, and
# terminal-app launchers.

OMA_AUTOSTART="$OMA_HYPR_DIR/autostart.conf"

# --- startup programs --------------------------------------------------------

# Lines are shown whether enabled or commented out, so disabling something is
# reversible from the same list rather than being a delete.
_startup_entries() {
  [[ -f $OMA_AUTOSTART ]] || return 0
  awk '
    {
      t = $0
      sub(/^[[:space:]]*/, "", t)
      enabled = 1
      if (t ~ /^#/) { enabled = 0; sub(/^#+[[:space:]]*/, "", t) }
      if (t ~ /^exec-once[[:space:]]*=/) {
        cmd = t
        sub(/^exec-once[[:space:]]*=[[:space:]]*/, "", cmd)
        printf "%s\t%s\t%s\n", NR, (enabled ? "on" : "off"), cmd
      }
    }
  ' "$OMA_AUTOSTART"
}

_startup_toggle() {
  local lineno="$1"
  local tmp
  tmp=$(mktemp) || return 1
  awk -v n="$lineno" '
    NR == n {
      t = $0
      sub(/^[[:space:]]*/, "", t)
      indent = $0; sub(/[^[:space:]].*$/, "", indent)
      if (t ~ /^#/) {
        sub(/^#+[[:space:]]*/, "", t)
        print indent t
      } else {
        print indent "# " t
      }
      next
    }
    { print }
  ' "$OMA_AUTOSTART" >"$tmp" && mv "$tmp" "$OMA_AUTOSTART" || {
    rm -f "$tmp"
    return 1
  }
}

_startup_menu() {
  while true; do
    oma_screen "Apps & Startup › Startup programs"

    local -a entries=()
    local n state cmd
    while IFS=$'\t' read -r n state cmd; do
      [[ -z $n ]] && continue
      ((${#cmd} > 52)) && cmd="${cmd:0:51}…"
      entries+=("$(printf 'line:%s\t%s\t%s' "$n" "$cmd" "$state")")
    done < <(_startup_entries)

    if ((${#entries[@]} == 0)); then
      oma_dim "No startup programs defined in autostart.conf."
      printf '\n'
    fi

    entries+=($'add\tAdd a startup program\t')
    entries+=($'edit\tEdit autostart.conf directly\t')
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Runs at login — enter toggles on/off" "${entries[@]}") || return 0

    case "$choice" in
    line:*)
      local lineno="${choice#line:}"
      oma_backup "$OMA_AUTOSTART"
      _startup_toggle "$lineno" && oma_ok "toggled — takes effect at next login"
      sleep 0.5
      ;;
    add)
      local cmd
      cmd=$(gum input --header "Command to run at login" \
        --placeholder "uwsm-app -- signal-desktop") || continue
      [[ -z $cmd ]] && continue
      oma_backup "$OMA_AUTOSTART"
      printf '\n# Added by omasettings on %s\nexec-once = %s\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$cmd" >>"$OMA_AUTOSTART"
      oma_ok "added — takes effect at next login"
      sleep 0.5
      ;;
    edit)
      oma_edit_file "$OMA_AUTOSTART"
      sleep 0.2
      ;;
    back | *) return 0 ;;
    esac
  done
}

# --- web apps and terminal apps ----------------------------------------------

_webapp_menu() {
  while true; do
    oma_screen "Apps & Startup › Web apps"

    local count
    count=$(grep -rls "omarchy-launch-webapp\|omarchy-launch-or-focus-webapp" \
      "$HOME/.local/share/applications" 2>/dev/null | grep -c .)

    local choice
    choice=$(oma_select "Web apps installed as desktop launchers" \
      "$(printf 'list\tShow installed web apps\t%s' "$count")" \
      $'add\tInstall a web app\t' \
      $'remove\tRemove a web app\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    list)
      oma_screen "Apps & Startup › Web apps"
      local -a found=()
      mapfile -t found < <(grep -rls "omarchy-launch-webapp\|omarchy-launch-or-focus-webapp" \
        "$HOME/.local/share/applications" 2>/dev/null |
        xargs -r -I{} sh -c 'printf "%s\n" "$(sed -n "s/^Name=//p" "{}" | head -1)"')
      if ((${#found[@]})); then
        printf '%s\n' "${found[@]}" | sed 's/^/    /'
      else
        oma_dim "None installed."
      fi
      oma_pause
      ;;
    add)
      local name url
      name=$(gum input --header "Web app name" --placeholder "Linear") || continue
      [[ -z $name ]] && continue
      url=$(gum input --header "URL" --placeholder "https://linear.app") || continue
      [[ -z $url ]] && continue
      oma_exec "Web app installed" omarchy webapp install "$name" "$url"
      ;;
    remove) oma_exec "Web app removed" omarchy webapp remove ;;
    back | *) return 0 ;;
    esac
  done
}

_tui_menu() {
  while true; do
    oma_screen "Apps & Startup › Terminal apps"

    local choice
    choice=$(oma_select "Terminal apps installed as desktop launchers" \
      $'add\tInstall a terminal app launcher\t' \
      $'remove\tRemove a terminal app launcher\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    add)
      local name cmd
      name=$(gum input --header "Launcher name" --placeholder "lazygit") || continue
      [[ -z $name ]] && continue
      cmd=$(gum input --header "Command to run" --placeholder "lazygit") || continue
      [[ -z $cmd ]] && continue
      oma_exec "Terminal app installed" omarchy tui install "$name" "$cmd"
      ;;
    remove) oma_exec "Terminal app removed" omarchy tui remove ;;
    back | *) return 0 ;;
    esac
  done
}

apps_menu() {
  while true; do
    oma_screen "Apps & Startup"

    local startup_count
    startup_count=$(_startup_entries | awk -F'\t' '$2 == "on"' | grep -c .)

    local choice
    choice=$(oma_select "Defaults, login programs, and installed launchers" \
      "$(printf 'browser\tDefault browser\t%s' "$(omarchy default browser 2>/dev/null)")" \
      "$(printf 'editor\tDefault editor\t%s' "$(omarchy default editor 2>/dev/null)")" \
      "$(printf 'terminal\tDefault terminal\t%s' "$(omarchy default terminal 2>/dev/null)")" \
      "$(printf 'startup\tStartup programs…\t%s enabled' "$startup_count")" \
      $'webapps\tWeb apps…\t' \
      $'tuis\tTerminal apps…\t' \
      $'install\tInstall optional software…\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    browser) _defaults_set browser "Default browser" chromium chrome brave brave-origin edge firefox zen ;;
    editor) _defaults_set editor "Default editor" code cursor zed sublime_text helix vim emacs nvim ;;
    terminal) _defaults_set terminal "Default terminal" alacritty foot ghostty kitty ;;
    startup) _startup_menu ;;
    webapps) _webapp_menu ;;
    tuis) _tui_menu ;;
    install) _system_group_menu install "Apps & Startup › Install" "Install optional software" ;;
    back | *) return 0 ;;
    esac
  done
}
