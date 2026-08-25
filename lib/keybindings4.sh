#!/bin/bash
# Keybindings on Omarchy 4.
#
# Omarchy 4 declares bindings in Lua, and every action is a closure. `hyprctl
# binds` therefore reports the dispatcher for all of them as "__lua" with an
# opaque index, so the Omarchy 3 approach — read the live binding and rewrite it
# as a config line — has nothing left to rewrite.
#
# Instead the active list comes from `omarchy menu keybindings --print`, which
# is what Omarchy itself shows, and the action behind a binding is recovered by
# finding the `o.bind(...)` call that declared it. That makes a real rebind
# possible: unbind the old combo, then re-issue the original call with a new
# one. Bindings whose source cannot be found can still be unbound.

# Lua source files that can declare bindings: Omarchy's defaults first, then the
# user's own, which are loaded afterwards and win.
_kb4_sources() {
  local f
  while IFS= read -r f; do [[ -f $f ]] && printf '%s\n' "$f"; done < <(
    find "$OMARCHY_PATH/default/hypr" -name '*.lua' 2>/dev/null
    printf '%s\n' "$OMA_HYPR_DIR"/*.lua
  )
}

# Hyprland prints combos as "SUPER SHIFT + F" while Lua declares them as
# "SUPER + SHIFT + F", and the modifier order is not guaranteed to match.
# Canonical form — sorted modifiers, uppercased, "+"-joined — lets the two be
# compared. The key itself keeps its case: xkbcommon is case-sensitive.
#
# Shared as an awk function so a whole list can be canonicalised in one pass;
# spawning awk per binding cost about a second across the ~230 of them.
_kb4_canon_awk='
  function canon(combo,   line, n, p, i, j, v, cnt, key, out) {
    line = combo
    gsub(/[[:space:]]*\+[[:space:]]*/, " ", line)
    sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
    n = split(line, p, /[[:space:]]+/)
    if (n == 0) return ""
    key = p[n]
    cnt = 0
    for (i = 1; i < n; i++) if (p[i] != "") mods[++cnt] = toupper(p[i])
    # Insertion sort: the modifier list is never more than a handful long.
    for (i = 2; i <= cnt; i++) {
      v = mods[i]
      for (j = i - 1; j >= 1 && mods[j] > v; j--) mods[j + 1] = mods[j]
      mods[j + 1] = v
    }
    out = ""
    for (i = 1; i <= cnt; i++) out = out mods[i] " + "
    for (i in mods) delete mods[i]
    return out key
  }
'

_kb4_canon() { printf '%s' "$1" | awk "$_kb4_canon_awk"'{ print canon($0) }'; }

# Active bindings as "combo<TAB>description", straight from Omarchy.
_kb4_active() {
  omarchy menu keybindings --print 2>/dev/null |
    sed -E 's/[[:space:]]+→[[:space:]]+/\t/' |
    awk -F'\t' 'NF == 2 { gsub(/[[:space:]]+$/, "", $1); print $1 "\t" $2 }'
}

# What a canonical combo is already bound to, if anything.
_kb4_conflict_for() {
  _kb4_active | awk -F'\t' -v want="$1" "$_kb4_canon_awk"'
    canon($1) == want { print $2; exit }'
}

# Declared bindings as "canon<TAB>combo<TAB>description<TAB>file<TAB>line".
# The declaring line is looked up again by number when it is actually needed,
# so commas and quotes inside the action never have to survive this pipeline.
_kb4_declared() {
  local -a files=()
  mapfile -t files < <(_kb4_sources)
  ((${#files[@]})) || return 0

  awk "$_kb4_canon_awk"'
    /^[[:space:]]*o\.bind(_toggle)?\("/ {
      line = $0
      sub(/^[[:space:]]*o\.bind(_toggle)?\("/, "", line)
      combo = line
      sub(/".*$/, "", combo)

      # Everything past the combo literal. A plain literal is followed by the
      # argument comma; anything else means the combo is built at load time
      # (Omarchy loops the workspace bindings as "SUPER + " .. key), and a
      # truncated prefix of one of those is not a binding this menu can move.
      rest = line
      sub(/^[^"]*"/, "", rest)
      if (rest !~ /^[[:space:]]*,/) next
      sub(/^[[:space:]]*,[[:space:]]*/, "", rest)
      desc = ""
      if (substr(rest, 1, 1) == "\"") {
        desc = substr(rest, 2)
        sub(/".*$/, "", desc)
      }
      if (combo != "")
        printf "%s\t%s\t%s\t%s\t%s\n", canon(combo), combo, desc, FILENAME, FNR
    }
  ' "${files[@]}"
}

# Find the declaration for a combo. Later files win, matching the load order.
_kb4_find() {
  local want
  want=$(_kb4_canon "$1")
  _kb4_declared | awk -F'\t' -v w="$want" '$1 == w { last = $0 } END { if (last) print last }'
}

_kb4_lines() {
  local combo desc
  while IFS=$'\t' read -r combo desc; do
    printf '%-34s %s\n' "$combo" "$desc"
  done < <(_kb4_active)
}

# Rewrite a declaring line with a different combo, leaving the action untouched.
_kb4_reissue() {
  local file="$1" lineno="$2" newcombo="$3"
  sed -n "${lineno}p" "$file" |
    sed -E "s/^([[:space:]]*o\.bind(_toggle)?\()\"[^\"]*\"/\1\"${newcombo//\//\\/}\"/" |
    sed -E 's/^[[:space:]]+//'
}

_kb4_ask_combo() {
  local prompt="$1" value
  value=$(gum input --header "$prompt" \
    --placeholder "SUPER + SHIFT + K" --value "${2:-}") || return 1
  value="${value//$'\n'/}"
  [[ -z $value ]] && return 1
  # Accept "SUPER SHIFT K", "SUPER SHIFT + K" and "SUPER + SHIFT + K" alike.
  _kb4_canon "$value"
}

_kb4_rebind() {
  local combo="$1" desc="$2"

  local rec dcombo dfile dline
  rec=$(_kb4_find "$combo")
  IFS=$'\t' read -r _ dcombo _ dfile dline <<<"$rec"

  local new
  new=$(_kb4_ask_combo "New combo for \"${desc:-$combo}\" (currently $combo)") || return 0
  [[ -z $new || $(_kb4_canon "$combo") == "$new" ]] && return 0

  local conflict
  conflict=$(_kb4_conflict_for "$new")

  oma_screen "Keybindings › Rebind"
  oma_dim "Action:  ${desc:-$combo}"
  oma_dim "From:    $combo"
  oma_dim "To:      $new"
  if [[ -z $dfile ]]; then
    printf '\n'
    oma_warn "Could not find the Lua call that declares this binding."
    oma_dim "It can be unbound, but not moved — omasettings has no action to re-issue."
    printf '\n'
    oma_confirm "Just unbind $combo?" || return 0
    oma_backup "$OMA_BINDINGS"
    {
      printf '\n-- Unbound by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
      printf 'hl.unbind("%s")\n' "${dcombo:-$combo}"
    } >>"$OMA_BINDINGS"
    oma_ok "unbound $combo"
    hypr_apply "$OMA_BINDINGS"
    oma_pause
    return 0
  fi

  oma_dim "Declared in: ${dfile/#$HOME/\~}:$dline"
  [[ -n $conflict ]] && {
    printf '\n'
    oma_warn "$new is already bound to: $conflict"
    oma_dim "It will be unbound so the new binding wins."
  }
  printf '\n'
  oma_confirm "Write this to $(basename "$OMA_BINDINGS")?" || return 0

  local reissued
  reissued=$(_kb4_reissue "$dfile" "$dline" "$new")
  [[ -z $reissued ]] && {
    oma_err "could not rewrite the binding"
    oma_pause
    return 1
  }

  oma_backup "$OMA_BINDINGS"
  {
    printf '\n-- Rebound by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'hl.unbind("%s")\n' "$dcombo"
    [[ -n $conflict ]] && printf 'hl.unbind("%s")\n' "$new"
    printf '%s\n' "$reissued"
  } >>"$OMA_BINDINGS"

  oma_ok "rebound to $new"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

_kb4_browse() {
  local -a lines=()
  mapfile -t lines < <(_kb4_lines | sort)
  ((${#lines[@]})) || {
    oma_err "could not read bindings"
    oma_dim "Try: omarchy menu keybindings --print"
    oma_pause
    return 1
  }

  local pick
  pick=$(printf '%s\n' "${lines[@]}" |
    gum filter --header "${#lines[@]} bindings — type to search, enter for details" \
      --height 20 --placeholder "e.g. screenshot, SUPER SHIFT, workspace" \
      --indicator "❯" --prompt "  ") || return 0
  [[ -z $pick ]] && return 0

  local combo="${pick%%  *}"
  combo="${combo%"${combo##*[![:space:]]}"}"
  local desc="${pick#"$combo"}"
  desc="${desc#"${desc%%[![:space:]]*}"}"

  local rec dfile dline
  rec=$(_kb4_find "$combo")
  IFS=$'\t' read -r _ _ _ dfile dline <<<"$rec"

  oma_screen "Keybindings › Detail"
  oma_dim "Combo:   $combo"
  oma_dim "Action:  ${desc:-(no description)}"
  if [[ -n $dfile ]]; then
    oma_dim "Source:  ${dfile/#$HOME/\~}:$dline"
    printf '\n'
    gum style --border rounded --border-foreground "$OMA_ACCENT" --padding "0 1" \
      "$(sed -n "${dline}p" "$dfile" | sed -E 's/^[[:space:]]+//')"
  else
    oma_dim "Source:  not found in the Lua config"
  fi
  printf '\n'

  local choice
  choice=$(oma_select "This binding" \
    $'rebind\tMove it to a different key\t' \
    $'unbind\tDisable it\t' \
    "$OMA_BACK") || return 0

  case "$choice" in
  rebind) _kb4_rebind "$combo" "$desc" ;;
  unbind)
    oma_confirm "Unbind $combo?" || return 0
    oma_backup "$OMA_BINDINGS"
    {
      printf '\n-- Unbound by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
      printf 'hl.unbind("%s")\n' "$combo"
    } >>"$OMA_BINDINGS"
    oma_ok "unbound $combo"
    hypr_apply "$OMA_BINDINGS"
    oma_pause
    ;;
  esac
}

_kb4_add() {
  oma_screen "Keybindings › Add"

  local combo
  combo=$(_kb4_ask_combo "Key combo for the new binding") || return 0

  local cmd
  cmd=$(gum input --header "Command to run" --placeholder "alacritty") || return 0
  [[ -z $cmd ]] && return 0

  local desc
  desc=$(gum input --header "Short description (shown in the keybindings menu)" \
    --placeholder "My terminal") || return 0

  # o.launch wraps the command with uwsm-app, which is how Omarchy starts
  # graphical apps so they land in the right systemd scope.
  local wrap="no"
  oma_confirm "Launch it as a desktop app (recommended for GUI programs)?" && wrap="yes"

  local conflict
  conflict=$(_kb4_conflict_for "$combo")

  oma_screen "Keybindings › Add"
  oma_dim "Combo:   $combo"
  oma_dim "Command: $cmd"
  [[ $wrap == yes ]] && oma_dim "Launch:  as a desktop app"
  [[ -n $conflict ]] && {
    printf '\n'
    oma_warn "$combo is already bound to: $conflict"
    oma_dim "It will be unbound first."
  }
  printf '\n'
  oma_confirm "Add this binding?" || return 0

  oma_backup "$OMA_BINDINGS"
  {
    printf '\n-- Added by omasettings on %s\n' "$(date '+%Y-%m-%d %H:%M')"
    [[ -n $conflict ]] && printf 'hl.unbind("%s")\n' "$combo"
    local action
    if [[ $wrap == yes ]]; then
      action=$(printf '{ launch = "%s" }' "${cmd//\"/\\\"}")
    else
      action=$(printf '"%s"' "${cmd//\"/\\\"}")
    fi
    if [[ -n $desc ]]; then
      printf 'o.bind("%s", "%s", %s)\n' "$combo" "${desc//\"/\\\"}" "$action"
    else
      printf 'o.bind("%s", nil, %s)\n' "$combo" "$action"
    fi
  } >>"$OMA_BINDINGS"

  oma_ok "added $combo"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

# Only what the user declared can be deleted; Omarchy's own bindings live in
# read-only defaults and are overridden with hl.unbind instead.
_kb4_remove() {
  [[ -f $OMA_BINDINGS ]] || return 0

  local -a lines=()
  mapfile -t lines < <(grep -nE '^[[:space:]]*(o\.bind(_toggle)?|hl\.unbind|hl\.bind)\(' \
    "$OMA_BINDINGS" | sed 's/\t/ /g')
  ((${#lines[@]})) || {
    oma_screen "Keybindings › Remove"
    oma_dim "No bindings declared in your $(basename "$OMA_BINDINGS") yet."
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
  oma_confirm "Delete line $lineno from $(basename "$OMA_BINDINGS")?" || return 0

  oma_backup "$OMA_BINDINGS"
  sed -i "${lineno}d" "$OMA_BINDINGS"
  oma_ok "removed"
  hypr_apply "$OMA_BINDINGS"
  oma_pause
}

_kb4_conflicts() {
  oma_screen "Keybindings › Shared combos"

  local -a dupes=()
  mapfile -t dupes < <(_kb4_active | cut -f1 | sort | uniq -d)

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
    _kb4_active | awk -F'\t' -v c="$c" '$1 == c { printf "    %-32s %s\n", $1, $2 }'
  done
  oma_pause
}

_keybindings_v4_menu() {
  while true; do
    oma_screen "Keybindings"

    local count
    count=$(_kb4_active | grep -c .)

    local choice
    choice=$(oma_select "Browse and customize keyboard shortcuts" \
      "$(printf 'browse\tBrowse & search all bindings\t%s active' "$count")" \
      $'add\tAdd a new binding\t' \
      $'remove\tRemove one of your bindings\t' \
      $'conflicts\tCombos running more than one action\t' \
      "$(printf 'edit\tEdit %s directly\t' "$(basename "$OMA_BINDINGS")")" \
      "$OMA_BACK") || return 0

    case "$choice" in
    browse) _kb4_browse ;;
    add) _kb4_add ;;
    remove) _kb4_remove ;;
    conflicts) _kb4_conflicts ;;
    edit)
      oma_edit_file "$OMA_BINDINGS" && hypr_apply "$OMA_BINDINGS"
      sleep 0.4
      ;;
    back | *) return 0 ;;
    esac
  done
}
