#!/bin/bash
# Monitor configuration.
#
# Neither generation stores monitors in the format the rest of the config uses,
# so this file carries its own reader and writer for each:
#
#   Omarchy 3  monitor = DP-2, 2560x1440@144, 0x0, 1
#   Omarchy 4  hl.monitor({ output = "DP-2", mode = "2560x1440@144", ... })
#
# Both ship a wildcard entry that applies to every output; a named entry added
# afterwards overrides it for that output only.

# Hyprland transform values.
_mon_transform_name() {
  case "$1" in
  0) printf 'normal' ;;
  1) printf '90° right' ;;
  2) printf '180° inverted' ;;
  3) printf '270° left' ;;
  4) printf 'flipped' ;;
  5) printf 'flipped 90°' ;;
  6) printf 'flipped 180°' ;;
  7) printf 'flipped 270°' ;;
  *) printf '%s' "$1" ;;
  esac
}

_mon_json() { hyprctl -j monitors all 2>/dev/null; }

# Current live geometry as "MODE|POSITION|SCALE|TRANSFORM|DISABLED"
_mon_state() {
  _mon_json | jq -r --arg n "$1" '
    .[] | select(.name == $n)
    | "\(.width)x\(.height)@\(.refreshRate | .*100 | round / 100)|\(.x)x\(.y)|\(.scale)|\(.transform)|\(.disabled)"' 2>/dev/null
}

# --- Omarchy 3: monitor = NAME, MODE, POSITION, SCALE -------------------------

# The per-monitor override line already in monitors.conf, if any.
_mon_conf_configured() {
  [[ -f $OMA_MONITORS ]] || return 0
  awk -v name="$1" '
    { t = $0; sub(/^[[:space:]]*/, "", t) }
    t ~ /^monitor[[:space:]]*=/ {
      rest = t
      sub(/^monitor[[:space:]]*=[[:space:]]*/, "", rest)
      split(rest, f, ",")
      nm = f[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", nm)
      if (nm == name) { sub(/^[^,]*,[[:space:]]*/, "", rest); print rest }
    }
  ' "$OMA_MONITORS" | tail -1
}

_mon_conf_write() {
  local name="$1" spec="$2"
  mkdir -p "$(dirname "$OMA_MONITORS")"
  [[ -f $OMA_MONITORS ]] || : >"$OMA_MONITORS"

  local tmp
  tmp=$(mktemp) || return 1
  awk -v name="$name" -v spec="$spec" '
    BEGIN { done = 0 }
    {
      line = $0
      t = line; sub(/^[[:space:]]*/, "", t)
      if (t ~ /^monitor[[:space:]]*=/) {
        rest = t
        sub(/^monitor[[:space:]]*=[[:space:]]*/, "", rest)
        split(rest, f, ",")
        nm = f[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", nm)
        if (nm == name) {
          if (!done) { print "monitor = " name ", " spec; done = 1 }
          next
        }
      }
      print line
    }
    END { if (!done) { print ""; print "monitor = " name ", " spec } }
  ' "$OMA_MONITORS" >"$tmp" && mv "$tmp" "$OMA_MONITORS" || {
    rm -f "$tmp"
    return 1
  }
}

_mon_conf_clear() {
  local name="$1"
  [[ -f $OMA_MONITORS ]] || return 0
  local tmp
  tmp=$(mktemp) || return 1
  awk -v name="$name" '
    {
      line = $0
      t = line; sub(/^[[:space:]]*/, "", t)
      if (t ~ /^monitor[[:space:]]*=/) {
        rest = t
        sub(/^monitor[[:space:]]*=[[:space:]]*/, "", rest)
        split(rest, f, ",")
        nm = f[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", nm)
        if (nm == name) next
      }
      print line
    }
  ' "$OMA_MONITORS" >"$tmp" && mv "$tmp" "$OMA_MONITORS" || {
    rm -f "$tmp"
    return 1
  }
}


# --- Omarchy 4: hl.monitor({ ... }) -------------------------------------------
#
# Omarchy writes one call per line, which is the form matched here. A
# hand-written multi-line call is left alone rather than half-rewritten.

_mon_lua_line_of() {
  [[ -f $OMA_MONITORS ]] || return 0
  grep -nE "^[[:space:]]*hl\.monitor\(\{.*output[[:space:]]*=[[:space:]]*\"$1\"" \
    "$OMA_MONITORS" 2>/dev/null | tail -1
}

# The configured override for a monitor, as a human-readable spec.
_mon_lua_configured() {
  local line
  line=$(_mon_lua_line_of "$1") || return 0
  [[ -z $line ]] && return 0
  # Strip the line number and the call wrapper, leaving the field list.
  printf '%s' "${line#*:}" |
    sed -E 's/^[[:space:]]*hl\.monitor\(\{[[:space:]]*//; s/[[:space:]]*\}\).*$//' |
    sed -E 's/output[[:space:]]*=[[:space:]]*"[^"]*",?[[:space:]]*//'
}

# Build the Lua call for a monitor from the fields the menu edits.
_mon_lua_call() {
  local name="$1" mode="$2" pos="$3" scale="$4" transform="$5"
  if [[ $mode == disable ]]; then
    printf 'hl.monitor({ output = "%s", disabled = true })' "$name"
    return
  fi
  local out
  out=$(printf 'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s' \
    "$name" "$mode" "$pos" "$scale")
  [[ -n $transform && $transform != 0 ]] && out+=", transform = $transform"
  printf '%s })' "$out"
}

_mon_lua_write() {
  local name="$1" call="$2"
  mkdir -p "$(dirname "$OMA_MONITORS")"
  [[ -f $OMA_MONITORS ]] || : >"$OMA_MONITORS"

  local existing lineno
  existing=$(_mon_lua_line_of "$name")
  lineno="${existing%%:*}"

  if [[ -n $lineno ]]; then
    local tmp
    tmp=$(mktemp) || return 1
    awk -v n="$lineno" -v call="$call" 'NR == n { print call; next } { print }' \
      "$OMA_MONITORS" >"$tmp" && mv "$tmp" "$OMA_MONITORS" || {
      rm -f "$tmp"
      return 1
    }
  else
    printf '\n%s\n' "$call" >>"$OMA_MONITORS"
  fi
}

_mon_lua_clear() {
  local name="$1"
  [[ -f $OMA_MONITORS ]] || return 0
  local existing lineno
  existing=$(_mon_lua_line_of "$name")
  lineno="${existing%%:*}"
  [[ -z $lineno ]] && return 0
  local tmp
  tmp=$(mktemp) || return 1
  awk -v n="$lineno" 'NR != n' "$OMA_MONITORS" >"$tmp" && mv "$tmp" "$OMA_MONITORS" || {
    rm -f "$tmp"
    return 1
  }
}

# --- format dispatch ----------------------------------------------------------

_mon_configured() {
  if oma_v4; then _mon_lua_configured "$1"; else _mon_conf_configured "$1"; fi
}

_mon_clear() {
  if oma_v4; then _mon_lua_clear "$1"; else _mon_conf_clear "$1"; fi
}

# Rewrite one field of the monitor's spec, keeping the others as they are now.
_mon_apply() {
  local name="$1" mode="$2" pos="$3" scale="$4" transform="$5"

  oma_backup "$OMA_MONITORS"
  local shown
  if oma_v4; then
    local call
    call=$(_mon_lua_call "$name" "$mode" "$pos" "$scale" "$transform")
    _mon_lua_write "$name" "$call" || return 1
    shown="$call"
  else
    local spec="$mode, $pos, $scale"
    [[ -n $transform && $transform != 0 ]] && spec+=", transform, $transform"
    _mon_conf_write "$name" "$spec" || return 1
    shown="$name → $spec"
  fi
  oma_ok "$shown"
  hypr_apply "$OMA_MONITORS"
  sleep 0.4
}

_mon_configure() {
  local name="$1"

  while true; do
    oma_screen "Display › $name"

    local state mode pos scale transform disabled
    state=$(_mon_state "$name")
    IFS='|' read -r mode pos scale transform disabled <<<"$state"

    local configured
    configured=$(_mon_configured "$name")

    oma_dim "$(_mon_json | jq -r --arg n "$name" '.[]|select(.name==$n)|.description')"
    local mon_file
    mon_file=$(basename "$OMA_MONITORS")
    [[ -n $configured ]] && oma_dim "$mon_file: $configured" ||
      oma_dim "$mon_file: no override (using the wildcard entry)"
    printf '\n'

    local choice
    choice=$(oma_select "Configure $name" \
      "$(printf 'mode\tResolution & refresh\t%s' "$mode")" \
      "$(printf 'scale\tScale\t%s' "$scale")" \
      "$(printf 'pos\tPosition\t%s' "$pos")" \
      "$(printf 'transform\tRotation\t%s' "$(_mon_transform_name "$transform")")" \
      "$(printf 'toggle\tOutput\t%s' "$([[ $disabled == true ]] && echo disabled || echo enabled)")" \
      $'reset\tRemove override (back to auto)\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    mode)
      local -a modes=()
      mapfile -t modes < <(_mon_json | jq -r --arg n "$name" \
        '.[] | select(.name==$n) | .availableModes[]' | sed 's/Hz$//')
      ((${#modes[@]})) || {
        oma_err "no modes reported for $name"
        oma_pause
        continue
      }
      modes+=("preferred")
      local pick
      pick=$(oma_pick "Resolution & refresh for $name" "$mode" "${modes[@]}") || continue
      [[ -n $pick ]] && _mon_apply "$name" "$pick" "$pos" "$scale" "$transform"
      ;;
    scale)
      local pick
      pick=$(oma_pick "Scale for $name — fractional scaling can blur some apps" \
        "$scale" 1 1.25 1.5 1.6 1.75 2 2.5 3 auto) || continue
      [[ -n $pick ]] && _mon_apply "$name" "$mode" "$pos" "$pick" "$transform"
      ;;
    pos)
      local pick
      pick=$(gum input --header "Position for $name (e.g. 0x0, 1920x0, or auto)" \
        --value "$pos") || continue
      [[ -z $pick ]] && continue
      if [[ $pick != auto && ! $pick =~ ^-?[0-9]+x-?[0-9]+$ ]]; then
        oma_err "expected WxH like 1920x0, or \"auto\""
        oma_pause
        continue
      fi
      _mon_apply "$name" "$mode" "$pick" "$scale" "$transform"
      ;;
    transform)
      local -a opts=()
      local t
      for t in 0 1 2 3 4 5 6 7; do opts+=("$t — $(_mon_transform_name "$t")"); done
      local pick
      pick=$(oma_pick "Rotation for $name" "$transform — $(_mon_transform_name "$transform")" "${opts[@]}") || continue
      [[ -z $pick ]] && continue
      _mon_apply "$name" "$mode" "$pos" "$scale" "${pick%% *}"
      ;;
    toggle)
      if [[ $disabled == true ]]; then
        _mon_apply "$name" "preferred" "auto" "1" 0
      else
        # Refuse to disable the only active output; that leaves no display.
        local active
        active=$(_mon_json | jq -r '[.[] | select(.disabled == false)] | length')
        if ((active <= 1)); then
          oma_err "$name is the only active output — disabling it would leave no display"
          oma_pause
          continue
        fi
        oma_confirm "Disable $name?" || continue
        oma_backup "$OMA_MONITORS"
        if oma_v4; then
          _mon_lua_write "$name" "$(_mon_lua_call "$name" disable)"
        else
          _mon_conf_write "$name" "disable"
        fi
        oma_ok "$name disabled"
        hypr_apply "$OMA_MONITORS"
        sleep 0.4
      fi
      ;;
    reset)
      oma_confirm "Remove the $name override from $(basename "$OMA_MONITORS")?" || continue
      oma_backup "$OMA_MONITORS"
      _mon_clear "$name"
      oma_ok "override removed"
      hypr_apply "$OMA_MONITORS"
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}

monitors_menu() {
  while true; do
    oma_screen "Display › Monitors"

    oma_hypr_live || {
      oma_err "Hyprland is not running, cannot query monitors"
      oma_pause
      return 1
    }

    local -a entries=()
    local n
    while IFS= read -r n; do
      [[ -z $n ]] && continue
      local state mode pos scale transform disabled
      state=$(_mon_state "$n")
      IFS='|' read -r mode pos scale transform disabled <<<"$state"
      if [[ $disabled == true ]]; then
        entries+=("$(printf 'mon:%s\t%s\tdisabled' "$n" "$n")")
      else
        entries+=("$(printf 'mon:%s\t%s\t%s  @%s  scale %s' "$n" "$n" "$mode" "$pos" "$scale")")
      fi
    done < <(_mon_json | jq -r '.[].name')

    entries+=("$(printf 'edit\tEdit %s directly\t' "$(basename "$OMA_MONITORS")")")
    entries+=("$OMA_BACK")

    local choice
    choice=$(oma_select "Connected outputs" "${entries[@]}") || return 0

    case "$choice" in
    mon:*) _mon_configure "${choice#mon:}" ;;
    edit)
      oma_edit_file "$OMA_MONITORS" && hypr_apply "$OMA_MONITORS"
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}
