#!/bin/bash
# Global search, a review of everything customized, and backup restore.

# The copy of each user config Omarchy ships, used to spot local changes.
OMA_DEFAULT_CONFIG="$OMARCHY_PATH/config"

# --- global search -----------------------------------------------------------

# Settings that are not in the registry cannot be edited generically, so search
# takes you to the menu that owns them. Each entry is "handler|display".
#
# The list differs between Omarchy generations — Waybar has settings the shell
# bar does not, and vice versa — so it is built at call time rather than being
# a fixed array.
OMA_SEARCH_EXTRA=()

_oma_search_index() {
  local bar
  bar=$(oma_bar_label)

  OMA_SEARCH_EXTRA=(
    "appearance_menu|Appearance › Theme"
    "appearance_menu|Appearance › Monospace font"
    "appearance_menu|Appearance › Wallpaper"
    "looknfeel_menu|Look & Feel › Window gaps mode"
    "bar_menu|$bar › Status bar visibility"
    "bar_menu|$bar › Bar position"
    "keybindings_menu|Keybindings › Browse & search shortcuts"
    "keybindings_menu|Keybindings › Add a binding"
    "keybindings_menu|Keybindings › Remove a binding"
    "monitors_menu|Display › Monitor resolution"
    "monitors_menu|Display › Monitor scale"
    "monitors_menu|Display › Monitor position"
    "monitors_menu|Display › Monitor rotation"
    "display_menu|Display › Brightness"
    "display_menu|Display › Night light"
    "display_menu|Display › Lock screen"
    "audio_menu|Audio › Output device"
    "audio_menu|Audio › Input device"
    "audio_menu|Audio › Output volume"
    "audio_menu|Audio › Microphone volume"
    "network_menu|Network › Wi-Fi"
    "network_menu|Network › Bluetooth"
    "network_menu|Network › Wi-Fi power saving"
    "network_menu|Network › DNS provider"
    "notifications_menu|Notifications › Do not disturb"
    "toggles_menu|Toggles › Screensaver"
    "toggles_menu|Toggles › Idle lock"
    "toggles_menu|Toggles › Touchpad"
    "toggles_menu|Toggles › Touchscreen"
    "apps_menu|Apps & Startup › Default browser"
    "apps_menu|Apps & Startup › Default editor"
    "apps_menu|Apps & Startup › Default terminal"
    "apps_menu|Apps & Startup › Startup programs"
    "apps_menu|Apps & Startup › Web apps"
    "apps_menu|Apps & Startup › Terminal apps"
    "power_menu|Power › Power profile"
    "power_menu|Power › Battery"
    "power_menu|Power › Hibernation"
    "security_menu|System › Passwordless sudo"
    "security_menu|System › Fingerprint unlock"
    "security_menu|System › FIDO2 security key"
    "security_menu|System › Snapshots"
    "system_menu|System › Update Omarchy"
    "system_menu|System › Timezone"
    "system_menu|System › Release channel"
    "system_menu|System › Boot screen"
    "system_menu|System › Restart a component"
    "system_menu|System › Reset a config to defaults"
  )

  if oma_v4; then
    OMA_SEARCH_EXTRA+=(
      "bar_menu|$bar › Widgets"
      "bar_menu|$bar › Transparent bar"
      "notifications_menu|Notifications › Notification history"
      "power_menu|Power › Lock after idle"
      "power_menu|Power › Screensaver after idle"
    )
  else
    OMA_SEARCH_EXTRA+=(
      "bar_menu|$bar › Modules"
      "bar_menu|$bar › Bar height"
      "bar_menu|$bar › Module spacing"
      "bar_menu|$bar › style.css"
      "notifications_menu|Notifications › Dismiss after"
      "notifications_menu|Notifications › Screen corner"
      "notifications_menu|Notifications › Width"
      "power_menu|Power › Idle timeouts"
    )
  fi
}


oma_search() {
  _oma_search_index

  local -a keys=() display=()
  local i e handler label
  local r_section r_label r_file r_hsec r_key r_live r_kind r_choices

  # Registry settings can be edited straight from the results.
  local lbl pad
  for i in "${!OMA_SETTINGS[@]}"; do
    _oma_reg_read "$i"
    keys+=("reg:$i")
    lbl="$(oma_reg_section_name "$r_section") › $r_label"
    pad=$((46 - ${#lbl}))
    ((pad < 1)) && pad=1
    display+=("$(printf '%s%*s%s' "$lbl" "$pad" "" \
      "$(hypr_show "$r_file" "$r_hsec" "$r_key" "$r_live" "$r_kind")")")
  done

  for e in "${OMA_SEARCH_EXTRA[@]}"; do
    handler="${e%%|*}"
    label="${e#*|}"
    keys+=("fn:$handler")
    display+=("$label")
  done

  local pick
  pick=$(printf '%s\n' "${display[@]}" |
    gum filter --header "Search all settings — ${#display[@]} entries" \
      --height 20 --placeholder "e.g. gaps, volume, theme, sudo, wallpaper" \
      --indicator "❯" --prompt "  ") || return 0
  [[ -z $pick ]] && return 0

  for i in "${!display[@]}"; do
    [[ ${display[$i]} == "$pick" ]] || continue
    case "${keys[$i]}" in
    reg:*) oma_reg_edit "${keys[$i]#reg:}" ;;
    fn:*) "${keys[$i]#fn:}" ;;
    esac
    return 0
  done
}

# --- what has been customized ------------------------------------------------

# User config files that differ from the copy Omarchy ships.
_oma_changed_files() {
  local -a candidates=("$HOME/.config/alacritty/alacritty.toml")
  if oma_v4; then
    candidates+=("$OMA_HYPR_DIR"/*.lua "$OMA_HYPR_DIR"/*.conf "$OMA_SHELL_JSON")
  else
    candidates+=("$OMA_HYPR_DIR"/*.conf "$HOME/.config/waybar/config.jsonc"
      "$HOME/.config/waybar/style.css")
  fi

  local f rel default
  for f in "${candidates[@]}"; do
    [[ -f $f ]] || continue
    rel="${f#"$HOME"/.config/}"
    default="$OMA_DEFAULT_CONFIG/$rel"
    [[ -f $default ]] || continue
    cmp -s "$f" "$default" || printf '%s\n' "$rel"
  done
}

oma_changed() {
  oma_screen "Changed from defaults"

  local -a idx=()
  mapfile -t idx < <(oma_reg_customized)

  local out=""
  if ((${#idx[@]})); then
    out+=$'Settings you have set explicitly\n\n'
    local i lbl pad
    local r_section r_label r_file r_hsec r_key r_live r_kind r_choices
    for i in "${idx[@]}"; do
      _oma_reg_read "$i"
      lbl="$(oma_reg_section_name "$r_section") › $r_label"
      pad=$((44 - ${#lbl}))
      ((pad < 1)) && pad=1
      out+=$(printf '  %s%*s%s' "$lbl" "$pad" "" \
        "$(hypr_get "$r_file" "$r_hsec" "$r_key")")
      out+=$'\n'
    done
  else
    out+=$'No Hyprland settings have been changed from the Omarchy defaults.\n'
  fi

  local -a files=()
  mapfile -t files < <(_oma_changed_files)
  if ((${#files[@]})); then
    out+=$'\nConfig files that differ from the shipped version\n\n'
    local f
    for f in "${files[@]}"; do out+="  ~/.config/$f"$'\n'; done
  fi

  printf '%s' "$out" | gum pager || printf '%s' "$out"
}

# --- backup restore ----------------------------------------------------------

# Every edit omasettings makes leaves a <file>.bak.<epoch> next to the original.
oma_restore() {
  while true; do
    oma_screen "Restore a backup"

    local -a baks=()
    mapfile -t baks < <(find "$HOME/.config" -maxdepth 3 -name '*.bak.*' \
      -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2)

    if ((${#baks[@]} == 0)); then
      oma_dim "No backups found under ~/.config."
      oma_pause
      return 0
    fi

    local -a entries=()
    local b target when
    for b in "${baks[@]}"; do
      target="${b%.bak.*}"
      when=$(date -d "@${b##*.bak.}" '+%Y-%m-%d %H:%M' 2>/dev/null)
      entries+=("$(printf '%s\t%s\t%s' "$b" "${target#"$HOME"/.config/}" "$when")")
    done
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "${#baks[@]} backup(s), newest first" "${entries[@]}") || return 0
    [[ $choice == back ]] && return 0

    local file="$choice"
    target="${file%.bak.*}"

    oma_screen "Restore a backup"
    oma_dim "Restore: $file"
    oma_dim "Over:    $target"
    printf '\n'

    if oma_has diff && [[ -f $target ]]; then
      local d
      d=$(diff -u "$target" "$file" 2>/dev/null | head -40)
      if [[ -n $d ]]; then
        printf '%s\n' "$d" | sed 's/^/    /'
        printf '\n'
      else
        oma_dim "The backup is identical to the current file."
        printf '\n'
      fi
    fi

    oma_confirm "Restore this backup?" || continue

    # Keep the version being replaced, so a restore is itself undoable.
    oma_backup "$target"
    cp "$file" "$target" || {
      oma_err "could not write $target"
      oma_pause
      continue
    }
    oma_ok "restored $target"

    case "$target" in
    "$OMA_HYPR_DIR"/*) hypr_apply "$target" ;;
    # shell.json hot-reloads on save, so a restored copy needs nothing.
    "$OMA_SHELL_JSON") oma_dim "the Omarchy shell picks this up on its own" ;;
    *waybar*) oma_spin "Waybar restarted" omarchy restart waybar ;;
    *mako*) oma_has makoctl && makoctl reload >/dev/null 2>&1 ;;
    esac
    oma_pause
  done
}
