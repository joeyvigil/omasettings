#!/bin/bash
# Waybar on Omarchy 3: which modules appear in the bar, and how the bar sits.
#
# Omarchy 4 replaced Waybar with the Quickshell-based Omarchy shell; bar.sh
# handles that generation and picks between the two.
#
# config.jsonc may carry comments, which jq cannot round-trip. Reads tolerate
# them; writes patch the single key in place with awk so the rest of the file —
# comments, ordering, formatting — survives untouched.

OMA_WAYBAR="$HOME/.config/waybar/config.jsonc"
OMA_WAYBAR_CSS="$HOME/.config/waybar/style.css"

_wb_json() {
  [[ -f $OMA_WAYBAR ]] || return 1
  jq . "$OMA_WAYBAR" 2>/dev/null && return 0
  # Fall back to stripping // comments for reading only.
  sed -E 's@(^|[[:space:]])//.*$@@' "$OMA_WAYBAR" | jq . 2>/dev/null
}

_wb_ok() { _wb_json >/dev/null 2>&1; }

# Modules Waybar defines a config block for — the set worth offering.
_wb_known_modules() {
  _wb_json | jq -r '
    to_entries[]
    | select(.value | type == "object")
    | select(.key | startswith("modules-") | not)
    | .key' 2>/dev/null | sort
}

_wb_modules_in() {
  _wb_json | jq -r --arg p "modules-$1" '.[$p][]? // empty' 2>/dev/null
}

_wb_position_of() {
  local m="$1" p
  for p in left center right; do
    _wb_modules_in "$p" | grep -qxF "$m" && {
      printf '%s' "$p"
      return
    }
  done
  printf 'off'
}

# Replace one top-level "key": value pair in place, whether its value sits on
# the same line or spreads over several (as modules-right usually does).
#
# Depth is tracked with string literals blanked out first: Waybar format strings
# are full of braces ("{icon}", "{capacity}%") and counting those would put the
# parser at the wrong nesting level and patch a module's key by mistake.
_wb_patch() {
  local key="$1" val="$2"
  local tmp
  tmp=$(mktemp) || return 1
  awk -v key="$key" -v val="$val" '
    function depth_delta(line,   s, o, c) {
      s = line
      gsub(/"([^"\\]|\\.)*"/, "", s)
      o = gsub(/\{/, "", s)
      c = gsub(/\}/, "", s)
      return o - c
    }
    BEGIN { depth = 0; inarr = 0; done = 0 }
    {
      atdepth = depth
      depth += depth_delta($0)

      if (!done && !inarr && atdepth == 1 && $0 ~ "^[[:space:]]*\"" key "\"[[:space:]]*:") {
        indent = $0; sub(/[^[:space:]].*$/, "", indent)
        # A value that opens a bracket at end of line continues on later lines.
        if ($0 ~ /[[{][[:space:]]*$/) { saveindent = indent; inarr = 1; next }
        comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
        printf "%s\"%s\": %s%s\n", indent, key, val, comma
        done = 1; next
      }

      if (inarr) {
        if ($0 ~ /^[[:space:]]*[]}][[:space:]]*,?[[:space:]]*$/) {
          comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
          printf "%s\"%s\": %s%s\n", saveindent, key, val, comma
          inarr = 0; done = 1
        }
        next
      }
      print
    }
    END { exit(done ? 0 : 1) }
  ' "$OMA_WAYBAR" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$OMA_WAYBAR"
}

_wb_json_array() {
  # Build ["a", "b"] from the arguments.
  local out="[" first=1 m
  for m in "$@"; do
    ((first)) || out+=", "
    out+="\"$m\""
    first=0
  done
  printf '%s]' "$out"
}

_wb_apply() {
  printf '\n'
  oma_spin "Waybar restarted" omarchy restart waybar
  sleep 0.4
}

# Move a module to a different section (or remove it entirely).
_wb_move() {
  local module="$1" target="$2"
  local pos
  local -a kept=()

  oma_backup "$OMA_WAYBAR"

  for pos in left center right; do
    kept=()
    local m
    while IFS= read -r m; do
      [[ -z $m || $m == "$module" ]] && continue
      kept+=("$m")
    done < <(_wb_modules_in "$pos")
    [[ $pos == "$target" ]] && kept+=("$module")

    _wb_patch "modules-$pos" "$(_wb_json_array "${kept[@]}")" || {
      oma_err "could not update modules-$pos"
      oma_pause
      return 1
    }
  done

  if ! _wb_ok; then
    oma_err "the edit left config.jsonc unparseable — restoring the backup"
    local backup
    backup=$(ls -t "$OMA_WAYBAR".bak.* 2>/dev/null | head -1)
    [[ -n $backup ]] && mv "$backup" "$OMA_WAYBAR"
    oma_pause
    return 1
  fi

  [[ $target == off ]] && oma_ok "$module removed from the bar" ||
    oma_ok "$module moved to $target"
  _wb_apply
}

_wb_modules_menu() {
  while true; do
    oma_screen "Waybar › Modules"

    local -a entries=() known=()
    mapfile -t known < <(_wb_known_modules)
    ((${#known[@]})) || {
      oma_err "no modules found in config.jsonc"
      oma_pause
      return 1
    }

    local m
    for m in "${known[@]}"; do
      entries+=("$(printf 'mod:%s\t%s\t%s' "$m" "$m" "$(_wb_position_of "$m")")")
    done
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Where each module sits in the bar" "${entries[@]}") || return 0
    [[ $choice == back ]] && return 0

    local module="${choice#mod:}"
    local current
    current=$(_wb_position_of "$module")

    local target
    target=$(oma_select "$module — currently $current" \
      $'left\tLeft\t' \
      $'center\tCenter\t' \
      $'right\tRight\t' \
      $'off\tHide it\t' \
      "$OMA_BACK") || continue
    [[ $target == back || $target == "$current" ]] && continue

    _wb_move "$module" "$target"
  done
}

waybar_menu() {
  while true; do
    oma_screen "Waybar"

    if ! _wb_ok; then
      oma_err "cannot parse $OMA_WAYBAR"
      oma_dim "Fix it by hand, or reset it with System › Reset a config to defaults."
      printf '\n'
      local c
      c=$(oma_select "Waybar" \
        $'edit\tEdit config.jsonc\t' \
        $'reset\tReset Waybar to Omarchy defaults\t' \
        "$OMA_BACK") || return 0
      case "$c" in
      edit) oma_edit_file "$OMA_WAYBAR" && _wb_apply ;;
      reset)
        oma_confirm "Reset Waybar config to the Omarchy default?" &&
          oma_exec "Waybar reset" omarchy refresh waybar
        ;;
      *) return 0 ;;
      esac
      continue
    fi

    local running count
    running=$(pgrep -x waybar >/dev/null 2>&1 && printf 'running' || printf 'hidden')
    count=$({
      _wb_modules_in left
      _wb_modules_in center
      _wb_modules_in right
    } | grep -c .)

    local choice
    choice=$(oma_select "Status bar layout and appearance" \
      "$(printf 'visible\tStatus bar\t%s' "$running")" \
      "$(printf 'modules\tModules…\t%s shown' "$count")" \
      "$(printf 'position\tBar position\t%s' "$(_wb_json | jq -r '.position // "top"')")" \
      "$(printf 'height\tBar height\t%s' "$(_wb_json | jq -r '.height // "auto"')")" \
      "$(printf 'spacing\tModule spacing\t%s' "$(_wb_json | jq -r '.spacing // 0')")" \
      $'style\tEdit style.css\t' \
      $'edit\tEdit config.jsonc\t' \
      $'restart\tRestart Waybar\t' \
      $'reset\tReset Waybar to defaults\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    visible)
      printf '\n'
      oma_spin "Status bar toggled" omarchy toggle waybar
      sleep 0.6
      ;;
    modules) _wb_modules_menu ;;
    position)
      local p
      p=$(oma_pick "Bar position" "$(_wb_json | jq -r '.position // "top"')" top bottom) || continue
      [[ -z $p ]] && continue
      oma_backup "$OMA_WAYBAR"
      _wb_patch position "\"$p\"" && oma_ok "bar position: $p"
      _wb_apply
      ;;
    height | spacing)
      local cur new
      cur=$(_wb_json | jq -r --arg k "$choice" '.[$k] // empty')
      new=$(gum input --header "Waybar $choice (empty resets to Omarchy's value)" \
        --value "$cur") || continue
      [[ -z $new ]] && continue
      [[ $new =~ ^[0-9]+$ ]] || {
        oma_err "$choice must be a whole number"
        oma_pause
        continue
      }
      oma_backup "$OMA_WAYBAR"
      _wb_patch "$choice" "$new" && oma_ok "$choice: $new"
      _wb_apply
      ;;
    style)
      oma_edit_file "$OMA_WAYBAR_CSS" && _wb_apply
      ;;
    edit)
      oma_edit_file "$OMA_WAYBAR" && _wb_apply
      ;;
    restart) _wb_apply ;;
    reset)
      oma_confirm "Reset Waybar config to the Omarchy default?" &&
        oma_exec "Waybar reset" omarchy refresh waybar
      ;;
    back | *) return 0 ;;
    esac
  done
}
