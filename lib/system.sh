#!/bin/bash
# System: updates, release channel, timezone, boot theme, and the generated
# "run any command in this group" menus.

# Menus for the restart/refresh/install/setup groups are generated from
# `omarchy commands --json`, so new Omarchy releases show up here for free.
_system_group_menu() {
  local group="$1" crumb="$2" header="$3"

  while true; do
    oma_screen "$crumb"

    local -a entries=()
    declare -A cmd_args=()
    local route name args summary
    # Tab is IFS whitespace, so an empty args field would collapse and shift
    # summary into it. Unit separator keeps every field positional.
    while IFS=$'\x1f' read -r route name args summary; do
      [[ -z $route ]] && continue
      cmd_args["$route"]="$args"
      [[ -n $args ]] && name="$name …"
      ((${#summary} > 44)) && summary="${summary:0:43}…"
      entries+=("$(printf '%s\t%s\t%s' "$route" "$name" "$summary")")
    done < <(omarchy commands --json 2>/dev/null |
      jq -r --arg g "$group" '.commands[]
             | select(.group == $g and (.hidden | not))
             | [.route, .name, .args, .summary] | join("\u001f")' 2>/dev/null)

    ((${#entries[@]})) || {
      oma_err "no commands found in group \"$group\""
      oma_pause
      return 1
    }
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "$header" "${entries[@]}") || return 0
    [[ $choice == back ]] && return 0

    local -a cmd=()
    read -ra cmd <<<"$choice"

    if [[ -n ${cmd_args["$choice"]:-} ]]; then
      local extra
      extra=$(gum input --header "$choice ${cmd_args["$choice"]}" \
        --placeholder "arguments") || continue
      [[ -n $extra ]] && read -ra extra_arr <<<"$extra" && cmd+=("${extra_arr[@]}")
    fi

    oma_screen "$crumb"
    oma_exec "$choice" "${cmd[@]}"
  done
}

_system_plymouth() {
  while true; do
    oma_screen "System › Boot screen"

    local choice
    choice=$(oma_select "Plymouth boot screen (needs sudo)" \
      $'match\tMatch an Omarchy theme\t' \
      $'reset\tRestore the Omarchy default\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    match)
      local -a themes=()
      mapfile -t themes < <(omarchy theme list 2>/dev/null)
      local pick
      pick=$(oma_pick "Boot screen theme" "$(omarchy theme current 2>/dev/null)" "${themes[@]}") || continue
      [[ -z $pick ]] && continue
      oma_exec "Boot screen set to $pick" omarchy plymouth set by theme "$pick"
      ;;
    reset)
      oma_confirm "Restore the default Omarchy boot screen?" &&
        oma_exec "Boot screen reset" omarchy plymouth reset
      ;;
    back | *) return 0 ;;
    esac
  done
}

system_menu() {
  while true; do
    oma_screen "System"

    local version tz
    # Omarchy 4 reports the packaged version through the CLI; Omarchy 3 only
    # had the file.
    version=$(omarchy version 2>/dev/null)
    [[ -z $version ]] && version=$(cat "$OMARCHY_PATH/version" 2>/dev/null)
    tz=$(timedatectl show -p Timezone --value 2>/dev/null)

    local choice
    choice=$(oma_select "Updates, channel, and system-wide configuration" \
      "$(printf 'update\tUpdate Omarchy and packages\t%s' "$version")" \
      "$(printf 'tz\tTimezone\t%s' "$tz")" \
      $'channel\tRelease channel\t' \
      $'security\tSecurity…\t' \
      $'snapshots\tSystem snapshots…\t' \
      $'restart\tRestart a component…\t' \
      $'refresh\tReset a config to defaults…\t' \
      $'install\tInstall optional software…\t' \
      $'setup\tSetup wizards…\t' \
      $'plymouth\tBoot screen…\t' \
      $'debug\tShow debug info\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    update)
      oma_screen "System › Update"
      oma_confirm "Update Omarchy and all system packages?" &&
        oma_exec "System updated" omarchy update
      ;;
    # shellcheck disable=SC2046  # the mapped command is split on purpose
    tz) oma_exec "Timezone updated" $(oma_cmd_line timezone) ;;
    channel)
      oma_screen "System › Channel"
      oma_warn "The channel decides which Omarchy branch and repos you track."
      printf '\n'
      local ch
      ch=$(oma_select "Release channel" \
        $'stable\tstable\trecommended' \
        $'rc\trc\trelease candidates' \
        $'edge\tedge\tlatest development' \
        $'dev\tdev\tlocal development' \
        "$OMA_BACK") || continue
      [[ $ch == back ]] && continue
      oma_confirm "Switch the release channel to \"$ch\"?" &&
        oma_exec "Channel set to $ch" omarchy channel set "$ch"
      ;;
    security) security_menu ;;
    snapshots) _sec_snapshots ;;
    restart) _system_group_menu restart "System › Restart" "Restart an Omarchy component" ;;
    refresh)
      oma_screen "System › Refresh"
      oma_warn "Refreshing overwrites your config with Omarchy's default."
      oma_dim "Omarchy backs up the existing file first."
      printf '\n'
      oma_confirm "Continue to the refresh menu?" &&
        _system_group_menu refresh "System › Refresh" "Reset a config to its Omarchy default"
      ;;
    install) _system_group_menu install "System › Install" "Install optional software" ;;
    setup) _system_group_menu setup "System › Setup" "Setup wizards" ;;
    plymouth) _system_plymouth ;;
    debug)
      oma_screen "System › Debug"
      # Omarchy 4 dropped `omarchy debug`; assemble the same picture from the
      # commands that replaced it.
      if oma_v4; then
        {
          printf 'Omarchy %s  (channel: %s)\n\n' \
            "$(omarchy version 2>/dev/null)" "$(omarchy channel current 2>/dev/null)"
          printf 'Hyprland:  %s\n' "$(hyprctl version 2>/dev/null | head -1)"
          printf 'Shell:     %s\n' \
            "$(pgrep -x quickshell >/dev/null 2>&1 && echo running || echo stopped)"
          printf 'Theme:     %s\n' "$(omarchy theme current 2>/dev/null)"
          printf 'Font:      %s\n\n' "$(omarchy font current 2>/dev/null)"
          printf 'Hyprland config errors:\n'
          hyprctl configerrors 2>&1 | sed 's/^/  /'
          printf '\nOmarchy packages:\n'
          omarchy version pkgs 2>&1 | sed 's/^/  /'
        } | gum pager || true
      else
        omarchy debug --no-sudo --print 2>&1 | gum pager || true
      fi
      ;;
    back | *) return 0 ;;
    esac
  done
}
