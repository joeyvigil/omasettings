#!/bin/bash
# Read/write settings inside Hyprland's brace-scoped .conf files (Omarchy 3),
# plus the shared machinery both config generations use: live-value lookup,
# reload-and-verify, and the generic setting editor.
#
# Omarchy sources ~/.config/hypr/*.conf after its own defaults, so anything
# written here overrides the stock value. Sections are addressed with dots
# ("input.touchpad"); an omitted key is created inside its section, and a
# commented-out key is uncommented in place so the file's own hints stay put.
#
# Omarchy 4's Lua equivalent lives in hyprlua.sh; hypr_get/set/unset below pick
# between them on the file extension.

# The config paths themselves live in compat.sh, which resolves the .conf/.lua
# split between Omarchy 3 and 4 before this file is sourced.

_hypr_walk='
  function rep(s, n,   i, o) { o = ""; for (i = 0; i < n; i++) o = o s; return o }
  function curpath(   i, s) {
    s = ""
    for (i = 1; i <= depth; i++) s = (i == 1 ? stack[i] : s "." stack[i])
    return s
  }
  function is_open(l) { return l ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*\{[[:space:]]*$/ }
  function open_name(l,   n) {
    n = l; sub(/^[[:space:]]*/, "", n); sub(/[[:space:]]*\{.*$/, "", n); return n
  }
  function is_close(l) { return l ~ /^[[:space:]]*\}/ }
'

# hypr_conf_get <file> <section> <key> — the effective configured value, or
# empty when the key is absent or commented out (Omarchy's default applies).
hypr_conf_get() {
  local file="$1" section="$2" key="$3"
  [[ -f $file ]] || return 0
  awk -v target="$section" -v key="$key" "$_hypr_walk"'
    BEGIN { depth = 0; val = "" }
    {
      line = $0
      if (is_open(line)) { stack[++depth] = open_name(line); next }
      if (is_close(line)) { if (depth > 0) { delete stack[depth]; depth-- } next }
      if (curpath() == target) {
        t = line
        sub(/^[[:space:]]*/, "", t)
        if (t ~ ("^" key "[[:space:]]*=")) {
          sub(/^[^=]*=[[:space:]]*/, "", t)
          sub(/[[:space:]]+#.*$/, "", t)
          sub(/[[:space:]]+$/, "", t)
          val = t
        }
      }
    }
    END { if (val != "") print val }
  ' "$file"
}

# hypr_conf_set <file> <section> <key> <value>
hypr_conf_set() {
  local file="$1" section="$2" key="$3" value="$4"
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || : >"$file"

  local tmp
  tmp=$(mktemp) || return 1
  awk -v target="$section" -v key="$key" -v value="$value" "$_hypr_walk"'
    function emit(path, pad,   i, n, p) {
      n = split(path, p, ".")
      for (i = 1; i <= n; i++) printf "%s%s {\n", rep(IND, pad + i - 1), p[i]
      printf "%s%s = %s\n", rep(IND, pad + n), key, value
      for (i = n; i >= 1; i--) printf "%s}\n", rep(IND, pad + i - 1)
    }
    BEGIN { depth = 0; done = 0; IND = "    " }
    {
      line = $0
      if (is_open(line)) { stack[++depth] = open_name(line); print line; next }

      if (is_close(line)) {
        cp = curpath()
        if (!done && cp == target) {
          printf "%s%s = %s\n", rep(IND, depth), key, value
          done = 1
        } else if (!done && cp != "" && index(target, cp ".") == 1) {
          # Parent section exists but the nested one does not; nest it in place.
          emit(substr(target, length(cp) + 2), depth)
          done = 1
        }
        if (depth > 0) { delete stack[depth]; depth-- }
        print line; next
      }

      if (curpath() == target) {
        t = line
        sub(/^[[:space:]]*/, "", t)
        sub(/^#+[[:space:]]*/, "", t)
        if (t ~ ("^" key "[[:space:]]*=")) {
          if (!done) {
            pre = line
            sub(/[^[:space:]].*$/, "", pre)
            if (pre == "") pre = rep(IND, depth)
            printf "%s%s = %s\n", pre, key, value
            done = 1
          }
          # Later duplicates would silently win on reload, so drop them.
          next
        }
      }
      print line
    }
    END { if (!done) { print ""; emit(target, 0) } }
  ' "$file" >"$tmp" && mv "$tmp" "$file" || {
    rm -f "$tmp"
    return 1
  }
}

# hypr_conf_unset <file> <section> <key> — comment the key out so Omarchy's
# default takes over again, keeping the previous value visible as a hint.
hypr_conf_unset() {
  local file="$1" section="$2" key="$3"
  [[ -f $file ]] || return 0

  local tmp
  tmp=$(mktemp) || return 1
  awk -v target="$section" -v key="$key" "$_hypr_walk"'
    BEGIN { depth = 0 }
    {
      line = $0
      if (is_open(line)) { stack[++depth] = open_name(line); print line; next }
      if (is_close(line)) { if (depth > 0) { delete stack[depth]; depth-- } print line; next }
      if (curpath() == target) {
        t = line
        sub(/^[[:space:]]*/, "", t)
        if (t ~ ("^" key "[[:space:]]*=")) {
          pre = line
          sub(/[^[:space:]].*$/, "", pre)
          printf "%s# %s\n", pre, t
          next
        }
      }
      print line
    }
  ' "$file" >"$tmp" && mv "$tmp" "$file" || {
    rm -f "$tmp"
    return 1
  }
}

# hypr_live <option> — the value Hyprland is actually running with right now,
# e.g. hypr_live general:gaps_in. Empty when Hyprland is not reachable.
hypr_live() {
  oma_hypr_live || return 0
  local v
  # Hyprland reports each option under a field named for its type. Booleans
  # come first because older builds folded them into "int", and a `false` read
  # as an int would otherwise look like no value at all. "css" holds per-side
  # values ("5 5 5 5") and "vec2" a pair, both of which the caller sees as a
  # space-separated string.
  v=$(hyprctl -j getoption "$1" 2>/dev/null |
    jq -r 'if has("bool") then .bool elif has("int") then .int
           elif has("float") then .float elif has("str") then .str
           elif has("css") then (.css | split(" ")
                                 | if (unique | length) == 1 then .[0] else join(" ") end)
           elif has("vec2") then (.vec2 | map(tostring) | join(" "))
           elif has("custom") then .custom
           else empty end | tostring' 2>/dev/null)

  # Hyprland reports unset strings with this sentinel; treat it as no value.
  [[ $v == "[[EMPTY]]" ]] && return 0

  # hyprctl emits floats padded to six decimals and jq preserves the literal.
  if [[ $v =~ ^-?[0-9]+\.[0-9]+$ ]]; then
    v="${v%"${v##*[!0]}"}"
    v="${v%.}"
  fi

  printf '%s' "$v"
}

# Hyprland reports booleans as 0/1 but accepts and documents true/false.
_hypr_norm() {
  if [[ $1 == bool ]]; then
    case "$2" in
    1) printf 'true' && return ;;
    0) printf 'false' && return ;;
    esac
  fi
  printf '%s' "$2"
}

# Reload and verify. Hyprland keeps running with a bad config, so a failed
# reload is easy to miss — surface the errors and offer the backup back.
hypr_apply() {
  local file="${1:-}"
  oma_hypr_live || {
    oma_warn "Hyprland is not running — change saved, it applies next login"
    return 0
  }

  hyprctl reload >/dev/null 2>&1
  local errs
  errs=$(hyprctl configerrors 2>/dev/null)

  if [[ -z $errs || $errs == *"no errors"* ]]; then
    oma_ok "applied"
    return 0
  fi

  oma_err "Hyprland reported config errors:"
  printf '%s\n' "$errs" | sed 's/^/    /' | head -20

  local backup
  backup=$(ls -t "$file".bak.* 2>/dev/null | head -1)
  if [[ -n $backup ]] && oma_confirm "Revert $(basename "$file") to the backup?"; then
    mv "$backup" "$file"
    hyprctl reload >/dev/null 2>&1
    oma_ok "reverted"
  fi
  return 1
}

# --- format dispatch ---------------------------------------------------------
#
# Omarchy 3 configures Hyprland in .conf files, Omarchy 4 in .lua. Both use the
# same dotted section addressing and the same key names, so the registry and
# every menu call these three functions and stay unaware of which they are on.

_hypr_is_lua() { [[ $1 == *.lua ]]; }

hypr_get() {
  if _hypr_is_lua "$1"; then hypr_lua_get "$@"; else hypr_conf_get "$@"; fi
}

# hypr_set <file> <section> <key> <value> [kind] — `kind` only matters for Lua,
# where it decides whether the value is quoted.
hypr_set() {
  if _hypr_is_lua "$1"; then hypr_lua_set "$@"; else hypr_conf_set "$1" "$2" "$3" "$4"; fi
}

hypr_unset() {
  if _hypr_is_lua "$1"; then hypr_lua_unset "$@"; else hypr_conf_unset "$@"; fi
}

# --- the generic setting editor ----------------------------------------------
#
# hypr_edit <file> <section> <key> <live-option> <kind> <label> [choices...]
#   kind: int | float | str | bool | choice
# Blank input (or picking "Omarchy default") unsets the key.
hypr_edit() {
  local file="$1" section="$2" key="$3" live="$4" kind="$5" label="$6"
  shift 6

  local configured current value
  configured=$(hypr_get "$file" "$section" "$key")
  current="$configured"
  [[ -z $current ]] && current=$(_hypr_norm "$kind" "$(hypr_live "$live")")

  local hint="current: ${current:-unset}"
  [[ -z $configured && -n $current ]] && hint+="  (Omarchy default)"

  case "$kind" in
  bool | choice)
    local -a entries=() choices=() o
    [[ $kind == bool ]] && choices=(true false) || choices=("$@")
    for o in "${choices[@]}"; do
      if [[ $o == "$current" ]]; then
        entries+=("$(printf '%s\t%s\t●' "$o" "$o")")
      else
        entries+=("$(printf '%s\t%s\t' "$o" "$o")")
      fi
    done
    entries+=("$(printf '__default__\tUse Omarchy default\t')")
    entries+=("$OMA_BACK")
    value=$(oma_select "$label — $hint" "${entries[@]}") || return 1
    ;;
  *)
    value=$(gum input --header "$label ($hint) — empty resets to default" \
      --value "$configured" --placeholder "${current:-value}") || return 1
    value="${value//$'\n'/}"
    [[ -z $value ]] && value="__default__"
    ;;
  esac

  [[ $value == back ]] && return 1

  if [[ $kind == int || $kind == float ]] && [[ $value != "__default__" ]]; then
    if ! [[ $value =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
      oma_err "\"$value\" is not a number"
      oma_pause
      return 1
    fi
  fi

  oma_backup "$file"
  if [[ $value == "__default__" ]]; then
    hypr_unset "$file" "$section" "$key" || return 1
    oma_ok "$label reset to the Omarchy default"
    hypr_apply "$file"
  else
    hypr_set "$file" "$section" "$key" "$value" "$kind" || return 1
    oma_ok "$label = $value"
    hypr_apply "$file" && hypr_verify "$live" "$value" "$kind"
  fi
  sleep 0.4
}

# Hyprland sources ~/.local/state/omarchy/toggles/hypr/*.conf after the user's
# own config, so an active Omarchy toggle can quietly win. Without this the
# setting just appears not to work.
hypr_verify() {
  local live_opt="$1" expected="$2" kind="$3"
  oma_hypr_live || return 0

  local live
  live=$(_hypr_norm "$kind" "$(hypr_live "$live_opt")")
  [[ -z $live || $live == "$expected" ]] && return 0

  oma_warn "Hyprland is still using $live"

  # Omarchy 3 writes these snippets as .conf and 4 as .lua, and Lua spells
  # hyphenated options with underscores, so match either.
  local key="${live_opt##*:}" culprit
  culprit=$(grep -rlsE "^[[:space:]]*(${key}|${key//-/_})[[:space:]]*=" \
    "$OMA_STATE_DIR/toggles/hypr" 2>/dev/null | head -1)

  if [[ -n $culprit ]]; then
    oma_dim "overridden by $(basename "$culprit"), which Hyprland sources last"
    [[ $culprit == *window-no-gaps* ]] &&
      oma_dim "switch it off under Look & Feel › Window gaps mode"
  fi
  oma_pause
}

# Compact "current value" string for menu right-hand columns.
# hypr_show <file> <section> <key> <live-option> [kind]
hypr_show() {
  local file="$1" section="$2" key="$3" live="$4" kind="${5:-}"
  local v
  v=$(hypr_get "$file" "$section" "$key")
  if [[ -n $v ]]; then
    printf '%s' "$v"
  else
    v=$(_hypr_norm "$kind" "$(hypr_live "$live")")
    [[ -n $v ]] && printf '%s (default)' "$v" || printf 'default'
  fi
}
