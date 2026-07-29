#!/bin/bash
# Notifications (mako).
#
# mako's config is flat `key=value` at the top, followed by `[criteria]` blocks
# that override settings for particular apps or modes. Only the top region is
# touched here — the criteria blocks are left exactly as they are.

OMA_MAKO="$HOME/.config/mako/config"

_mako_get() {
  [[ -f $OMA_MAKO ]] || return 0
  awk -v key="$1" '
    /^[[:space:]]*\[/ { exit }
    {
      t = $0
      sub(/^[[:space:]]*/, "", t)
      if (t ~ ("^" key "[[:space:]]*=")) {
        sub(/^[^=]*=[[:space:]]*/, "", t)
        val = t
      }
    }
    END { if (val != "") print val }
  ' "$OMA_MAKO"
}

_mako_set() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$OMA_MAKO")"
  [[ -f $OMA_MAKO ]] || : >"$OMA_MAKO"

  local tmp
  tmp=$(mktemp) || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    {
      # The first criteria block ends the global region; insert before it.
      if (!done && $0 ~ /^[[:space:]]*\[/) {
        print key "=" value
        print ""
        done = 1
        print
        next
      }
      if (!done) {
        t = $0
        sub(/^[[:space:]]*/, "", t)
        sub(/^#+[[:space:]]*/, "", t)
        if (t ~ ("^" key "[[:space:]]*=")) {
          print key "=" value
          done = 1
          next
        }
      }
      print
    }
    END { if (!done) print key "=" value }
  ' "$OMA_MAKO" >"$tmp" && mv "$tmp" "$OMA_MAKO" || {
    rm -f "$tmp"
    return 1
  }
}

# A key absent from the config means mako's own default applies.
_mako_show() {
  local v
  v=$(_mako_get "$1")
  [[ -n $v ]] && printf '%s' "$v" || printf 'default'
}

_mako_apply() {
  oma_has makoctl || return 0
  if makoctl reload >/dev/null 2>&1; then
    oma_ok "applied"
  else
    oma_warn "mako is not running — the change applies next time it starts"
  fi
  sleep 0.4
}

_mako_edit() {
  local key="$1" label="$2" kind="$3"
  shift 3

  local current="${*:+}"
  current=$(_mako_get "$key")

  local value
  if (($#)); then
    value=$(oma_pick "$label — current: ${current:-default}" "$current" "$@") || return 0
  else
    value=$(gum input --header "$label (current: ${current:-default})" --value "$current") || return 0
    value="${value//$'\n'/}"
  fi
  [[ -z $value ]] && return 0

  if [[ $kind == int && ! $value =~ ^[0-9]+$ ]]; then
    oma_err "$label must be a whole number"
    oma_pause
    return 1
  fi

  oma_backup "$OMA_MAKO"
  _mako_set "$key" "$value" || return 1
  oma_ok "$label = $value"
  _mako_apply
}

notifications_menu() {
  while true; do
    oma_screen "Notifications"

    if [[ ! -f $OMA_MAKO ]]; then
      oma_err "no mako config at $OMA_MAKO"
      oma_pause
      return 1
    fi

    local dnd
    dnd=$(oma_has makoctl && makoctl mode 2>/dev/null | grep -q 'do-not-disturb' &&
      printf 'on' || printf 'off')

    local timeout
    timeout=$(_mako_get default-timeout)
    [[ -n $timeout ]] && timeout="${timeout} ms" || timeout="default"

    local choice
    choice=$(oma_select "Notification behaviour and appearance" \
      "$(printf 'dnd\tDo not disturb\t%s' "$dnd")" \
      "$(printf 'timeout\tDismiss after\t%s' "$timeout")" \
      "$(printf 'anchor\tScreen corner\t%s' "$(_mako_show anchor)")" \
      "$(printf 'width\tWidth\t%s' "$(_mako_show width)")" \
      "$(printf 'height\tMax height\t%s' "$(_mako_show height)")" \
      "$(printf 'maxvis\tMax visible at once\t%s' "$(_mako_show max-visible)")" \
      "$(printf 'border\tBorder size\t%s' "$(_mako_show border-size)")" \
      $'history\tShow recent notifications\t' \
      $'edit\tEdit the mako config directly\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    dnd)
      printf '\n'
      oma_spin "Do not disturb toggled" omarchy toggle notification silencing
      sleep 0.6
      ;;
    timeout) _mako_edit default-timeout "Dismiss after (ms, 0 = never)" int ;;
    anchor) _mako_edit anchor "Screen corner" str \
      top-right top-center top-left bottom-right bottom-center bottom-left center ;;
    width) _mako_edit width "Width (px)" int ;;
    height) _mako_edit height "Max height (px)" int ;;
    maxvis) _mako_edit max-visible "Max visible at once" int ;;
    border) _mako_edit border-size "Border size (px)" int ;;
    history)
      oma_screen "Notifications › History"
      if oma_has makoctl; then
        makoctl history 2>/dev/null | gum pager || {
          oma_dim "No notification history."
          oma_pause
        }
      else
        oma_err "makoctl is not available"
        oma_pause
      fi
      ;;
    edit)
      oma_edit_file "$OMA_MAKO" && _mako_apply
      ;;
    back | *) return 0 ;;
    esac
  done
}
