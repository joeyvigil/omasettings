#!/bin/bash
# Read and write ~/.config/omarchy/shell.json (Omarchy 4).
#
# The bar, notification daemon, and idle timeouts all live in one Quickshell
# process configured by this single file. It is strict JSON — no comments — so
# unlike Waybar's jsonc it round-trips through jq safely.
#
# The shell hot-reloads the file on save, so writes need no restart. Layout
# changes still go through `omarchy bar`, which knows the placement rules;
# jq is only used for the settings no command covers.

# The file is created on demand: a missing shell.json means "all defaults".
_shell_json() {
  [[ -f $OMA_SHELL_JSON ]] && jq . "$OMA_SHELL_JSON" 2>/dev/null && return 0
  printf '{}'
}

shell_json_ok() { [[ ! -f $OMA_SHELL_JSON ]] || jq -e . "$OMA_SHELL_JSON" >/dev/null 2>&1; }

# shell_get <jq-path> [default] — e.g. shell_get '.idle.lock' 300
shell_get() {
  local v
  v=$(_shell_json | jq -r "$1 // empty" 2>/dev/null)
  [[ -n $v && $v != null ]] && printf '%s' "$v" || printf '%s' "${2:-}"
}

# shell_set <jq-path> <json-value> — e.g. shell_set '.idle.lock' 600
# The value is raw JSON, so strings must arrive already quoted.
shell_set() {
  local path="$1" value="$2"
  mkdir -p "$(dirname "$OMA_SHELL_JSON")"

  local tmp
  tmp=$(mktemp) || return 1
  # Omarchy's own defaults fill in anything absent, so writing only the changed
  # key keeps the file small and lets future default changes still reach the user.
  if _shell_json | jq --argjson v "$value" "$path = \$v" >"$tmp" 2>/dev/null; then
    # Preserve the mode of the original: Omarchy creates it 0600.
    [[ -f $OMA_SHELL_JSON ]] && chmod --reference="$OMA_SHELL_JSON" "$tmp" 2>/dev/null
    mv "$tmp" "$OMA_SHELL_JSON"
  else
    rm -f "$tmp"
    return 1
  fi
}

# The widgets currently placed in the bar, as "id<TAB>section".
shell_bar_placements() {
  _shell_json | jq -r '
    .bar.layout // {}
    | to_entries[]
    | .key as $section
    | (.value // [])[]
    | "\(.id)\t\($section)"' 2>/dev/null
}

# Which section a widget sits in, or "off" when it is not on the bar.
shell_bar_section_of() {
  local id="$1" found
  found=$(shell_bar_placements | awk -F'\t' -v id="$id" '$1 == id { print $2; exit }')
  printf '%s' "${found:-off}"
}

# The shell reloads shell.json itself; this is for changes made another way.
shell_restart() { oma_spin "Omarchy shell restarted" omarchy restart shell; }

# shell_ipc <target> <method> [args...] — talk to the running shell and print
# its reply. Empty (non-zero) when the shell is not up. Note that `omarchy
# shell -q` swallows the reply, so queries must not pass it.
shell_ipc() { omarchy shell "$@" 2>/dev/null; }
