#!/bin/bash
# Read/write settings inside Omarchy 4's Lua Hyprland config.
#
# Omarchy 4 configures Hyprland in Lua. Settings live in nested tables passed
# to hl.config(), and user files are loaded after Omarchy's defaults, so
# anything written here overrides the stock value:
#
#   hl.config({
#     decoration = {
#       rounding = 10,
#       blur = { enabled = true },
#     },
#   })
#
# Sections are addressed with dots ("decoration.blur"), matching the .conf
# addressing hyprconf.sh uses, so the settings registry is shared between both
# Omarchy generations.
#
# Commented-out lines are inert here. Omarchy ships these files full of
# commented example blocks that double as the documentation, and uncommenting
# one line out of a commented table would leave a dangling assignment that
# breaks the file. Writes therefore only ever touch live code, and leave the
# commented hints exactly where they are.

# Hyprland's Lua bridge spells hyphenated option names with underscores:
# `tap-to-click` is written `tap_to_click`. Live-option lookups keep the hyphen.
_lua_key() { printf '%s' "${1//-/_}"; }

# Shared structure walker. A line that starts with `--` is a comment and never
# opens, closes, or contributes a value.
_hypr_lua_walk='
  function rep(s, n,   i, o) { o = ""; for (i = 0; i < n; i++) o = o s; return o }
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function is_comment(l) { return trim(l) ~ /^--/ }
  function curpath(   i, s) {
    s = ""
    for (i = 1; i <= depth; i++) s = (i == 1 ? stack[i] : s "." stack[i])
    return s
  }
  # `hl.config({` opens the outer scope without contributing a path element.
  function is_config_open(l) { return trim(l) ~ /^hl\.config\(\{$/ }
  function is_config_close(l) { return trim(l) ~ /^\}\)[,;]?$/ }
  # `name = {` opens a nested table.
  function is_open(l) { return trim(l) ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*\{$/ }
  function open_name(l,   n) { n = trim(l); sub(/[[:space:]]*=.*$/, "", n); return n }
  function is_close(l) { return trim(l) ~ /^\}[,;]?$/ }
  # Strip a trailing comma and any inline `--` comment from a value.
  function clean_value(v) {
    v = trim(v)
    sub(/[[:space:]]*--.*$/, "", v)
    v = trim(v)
    sub(/,$/, "", v)
    return trim(v)
  }
'

# hypr_lua_get <file> <section> <key> — the configured value, or empty when the
# key is absent (i.e. Omarchy default applies). Strings come back unquoted.
hypr_lua_get() {
  local file="$1" section="$2" key
  key=$(_lua_key "$3")
  [[ -f $file ]] || return 0

  awk -v target="$section" -v key="$key" "$_hypr_lua_walk"'
    BEGIN { depth = 0; inconfig = 0; val = "" }
    {
      line = $0
      if (is_comment(line)) next

      if (is_config_open(line)) { inconfig = 1; depth = 0; next }
      if (!inconfig) next
      if (is_config_close(line)) { inconfig = 0; depth = 0; next }

      if (is_open(line)) { stack[++depth] = open_name(line); next }
      if (is_close(line)) { if (depth > 0) { delete stack[depth]; depth-- } next }

      if (curpath() == target) {
        t = trim(line)
        if (t ~ ("^" key "[[:space:]]*=")) {
          sub(/^[^=]*=/, "", t)
          val = clean_value(t)
        }
      }
    }
    END {
      # Unquote strings; leave numbers, booleans, and inline tables as they are.
      if (val ~ /^".*"$/) val = substr(val, 2, length(val) - 2)
      if (val != "") print val
    }
  ' "$file"
}

# Format a value the way Lua needs it. Numbers, booleans, and inline tables go
# in bare; everything else is a string and gets quoted.
_lua_value() {
  local kind="$1" v="$2"
  case "$kind" in
  int | float | bool) printf '%s' "$v" && return ;;
  esac
  if [[ $v =~ ^-?[0-9]+([.][0-9]+)?$ || $v == true || $v == false || $v =~ ^\{.*\}$ ]]; then
    printf '%s' "$v"
  else
    printf '"%s"' "${v//\"/\\\"}"
  fi
}

# hypr_lua_set <file> <section> <key> <value> [kind]
#
# Replaces the assignment in place when it already exists, nests it into the
# innermost existing ancestor table when only part of the path is there, and
# otherwise appends a fresh hl.config block.
hypr_lua_set() {
  local file="$1" section="$2" key value kind="${5:-}"
  key=$(_lua_key "$3")
  value=$(_lua_value "$kind" "$4")

  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || : >"$file"

  local tmp
  tmp=$(mktemp) || return 1
  awk -v target="$section" -v key="$key" -v value="$value" "$_hypr_lua_walk"'
    # Emit the missing part of a path as nested tables, innermost holding the
    # assignment, indented to sit under an existing table at `pad` levels.
    function emit(path, pad,   i, n, p) {
      n = split(path, p, ".")
      for (i = 1; i <= n; i++) printf "%s%s = {\n", rep(IND, pad + i - 1), p[i]
      printf "%s%s = %s,\n", rep(IND, pad + n), key, value
      for (i = n; i >= 1; i--) printf "%s},\n", rep(IND, pad + i - 1)
    }
    BEGIN { depth = 0; inconfig = 0; done = 0; IND = "  " }
    {
      line = $0
      # Once the value is placed, the rest of the file passes through as-is.
      if (done || is_comment(line)) { print line; next }

      if (is_config_open(line)) { inconfig = 1; depth = 0; print line; next }
      if (!inconfig) { print line; next }
      if (is_config_close(line)) { inconfig = 0; depth = 0; print line; next }

      if (is_open(line)) { stack[++depth] = open_name(line); print line; next }

      if (is_close(line)) {
        cp = curpath()
        if (!done && cp == target) {
          printf "%s%s = %s,\n", rep(IND, depth + 1), key, value
          done = 1
        } else if (!done && cp != "" && index(target, cp ".") == 1) {
          # An ancestor table exists but the nested one does not; nest it here.
          emit(substr(target, length(cp) + 2), depth + 1)
          done = 1
        }
        if (depth > 0) { delete stack[depth]; depth-- }
        print line; next
      }

      if (curpath() == target) {
        t = trim(line)
        if (t ~ ("^" key "[[:space:]]*=")) {
          if (!done) {
            pre = line; sub(/[^[:space:]].*$/, "", pre)
            if (pre == "") pre = rep(IND, depth + 1)
            printf "%s%s = %s,\n", pre, key, value
            done = 1
          }
          # A later duplicate would silently win on reload, so drop it.
          next
        }
      }
      print line
    }
    END {
      if (!done) {
        printf "\n-- Set by omasettings\nhl.config({\n"
        emit(target, 1)
        printf "})\n"
      }
    }
  ' "$file" >"$tmp" && mv "$tmp" "$file" || {
    rm -f "$tmp"
    return 1
  }
}

# hypr_lua_unset <file> <section> <key> — comment the assignment out so
# Omarchy's default takes over again, keeping the value visible as a hint.
hypr_lua_unset() {
  local file="$1" section="$2" key
  key=$(_lua_key "$3")
  [[ -f $file ]] || return 0

  local tmp
  tmp=$(mktemp) || return 1
  awk -v target="$section" -v key="$key" "$_hypr_lua_walk"'
    BEGIN { depth = 0; inconfig = 0 }
    {
      line = $0
      if (is_comment(line)) { print line; next }

      if (is_config_open(line)) { inconfig = 1; depth = 0; print line; next }
      if (!inconfig) { print line; next }
      if (is_config_close(line)) { inconfig = 0; depth = 0; print line; next }

      if (is_open(line)) { stack[++depth] = open_name(line); print line; next }
      if (is_close(line)) { if (depth > 0) { delete stack[depth]; depth-- } print line; next }

      if (curpath() == target) {
        t = trim(line)
        if (t ~ ("^" key "[[:space:]]*=")) {
          pre = line; sub(/[^[:space:]].*$/, "", pre)
          printf "%s-- %s\n", pre, t
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
