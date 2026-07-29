#!/bin/bash
# Shared theming, prompts, and output helpers for omasettings.

OMA_THEME_DIR="$HOME/.config/omarchy/current/theme"
OMA_HYPR_DIR="$HOME/.config/hypr"
OMA_STATE_DIR="$HOME/.local/state/omarchy"
OMA_BACK=$'back\t← Back\t'
OMA_QUIT=$'quit\tQuit\t'

# --- theming -----------------------------------------------------------------

_oma_toml() {
  # _oma_toml <file> <key> -> bare value of `key = "value"`
  sed -nE "s/^$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" 2>/dev/null | head -1
}

# Read the live theme rather than trusting the GUM_* env vars Hyprland exported
# at session start, so switching themes inside omasettings restyles it at once.
oma_load_theme() {
  OMA_FG="#cdd6f4" OMA_ACCENT="#89b4fa" OMA_CURSOR="#f5e0dc" OMA_DIM="#6c7086"

  local colors="$OMA_THEME_DIR/colors.toml" v
  if [[ -r $colors ]]; then
    v=$(_oma_toml "$colors" foreground) && [[ -n $v ]] && OMA_FG="$v"
    v=$(_oma_toml "$colors" accent) && [[ -n $v ]] && OMA_ACCENT="$v"
    v=$(_oma_toml "$colors" cursor) && [[ -n $v ]] && OMA_CURSOR="$v"
    v=$(_oma_toml "$colors" color8) && [[ -n $v ]] && OMA_DIM="$v"
  fi

  # Foregrounds only. Painting backgrounds would fight the terminal's own
  # background wherever omasettings is run from a non-themed terminal.
  export GUM_CHOOSE_CURSOR_FOREGROUND="$OMA_ACCENT"
  export GUM_CHOOSE_HEADER_FOREGROUND="$OMA_DIM"
  export GUM_CHOOSE_ITEM_FOREGROUND="$OMA_FG"
  export GUM_CHOOSE_SELECTED_FOREGROUND="$OMA_ACCENT"
  export GUM_FILTER_PROMPT_FOREGROUND="$OMA_ACCENT"
  export GUM_FILTER_INDICATOR_FOREGROUND="$OMA_ACCENT"
  export GUM_FILTER_MATCH_FOREGROUND="$OMA_ACCENT"
  export GUM_FILTER_TEXT_FOREGROUND="$OMA_FG"
  export GUM_FILTER_HEADER_FOREGROUND="$OMA_DIM"
  export GUM_FILTER_PLACEHOLDER_FOREGROUND="$OMA_DIM"
  export GUM_FILTER_CURSOR_TEXT_FOREGROUND="$OMA_CURSOR"
  export GUM_INPUT_PROMPT_FOREGROUND="$OMA_ACCENT"
  export GUM_INPUT_CURSOR_FOREGROUND="$OMA_CURSOR"
  export GUM_INPUT_HEADER_FOREGROUND="$OMA_DIM"
  export GUM_INPUT_PLACEHOLDER_FOREGROUND="$OMA_DIM"
  export GUM_CONFIRM_PROMPT_FOREGROUND="$OMA_FG"
  export GUM_CONFIRM_SELECTED_FOREGROUND="$OMA_ACCENT"
  export GUM_CONFIRM_UNSELECTED_FOREGROUND="$OMA_DIM"
  export GUM_SPIN_SPINNER_FOREGROUND="$OMA_ACCENT"
  export GUM_SPIN_TITLE_FOREGROUND="$OMA_FG"
  export GUM_FILE_CURSOR_FOREGROUND="$OMA_CURSOR"
  export GUM_FILE_DIRECTORY_FOREGROUND="$OMA_ACCENT"
  export GUM_FILE_FILE_FOREGROUND="$OMA_FG"
  export GUM_PAGER_FOREGROUND="$OMA_FG"
}

# --- guards ------------------------------------------------------------------

oma_require() {
  local missing=() c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if ((${#missing[@]})); then
    printf 'omasettings: missing required command(s): %s\n' "${missing[*]}" >&2
    return 1
  fi
}

oma_has() { command -v "$1" >/dev/null 2>&1; }

# True when a live Hyprland instance is reachable, so display-only features can
# degrade gracefully instead of erroring out over a TTY or SSH session.
oma_hypr_live() { oma_has hyprctl && hyprctl version >/dev/null 2>&1; }

# --- layout ------------------------------------------------------------------

oma_width() {
  local w=${COLUMNS:-0}
  ((w == 0)) && w=$(tput cols 2>/dev/null || echo 80)
  w=$((w - 4))
  ((w > 74)) && w=74
  ((w < 24)) && w=24
  printf '%s' "$w"
}

oma_screen() {
  clear
  local crumb="Omarchy Settings"
  [[ -n ${1:-} ]] && crumb+="  ›  $1"
  gum style --border rounded --border-foreground "$OMA_ACCENT" \
    --foreground "$OMA_FG" --padding "0 2" --margin "1 0" \
    --width "$(oma_width)" "󰒓  $crumb"
}

# --- messages ----------------------------------------------------------------

oma_ok() { gum style --foreground "$OMA_ACCENT" "  ✓ $*"; }
oma_warn() { gum style --foreground "#e0af68" "  ! $*"; }
oma_err() { gum style --foreground "#f7768e" "  ✗ $*"; }
oma_dim() { gum style --foreground "$OMA_DIM" "  $*"; }

oma_pause() {
  printf '\n'
  gum style --foreground "$OMA_DIM" "  press enter to continue"
  read -r _ </dev/tty
}

oma_confirm() { gum confirm "$1" --affirmative "Yes" --negative "Cancel"; }

# --- running commands --------------------------------------------------------

# Quick, non-interactive commands: spinner plus captured output on failure.
oma_spin() {
  local msg="$1"
  shift
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  if ((rc == 0)); then
    oma_ok "$msg"
  else
    oma_err "$msg failed"
    [[ -n $out ]] && printf '%s\n' "$out" | sed 's/^/    /'
  fi
  return $rc
}

# Commands that may prompt, sudo, or stream output: run them attached to the tty.
oma_exec() {
  local msg="$1"
  shift
  oma_dim "$ $*"
  printf '\n'
  "$@"
  local rc=$?
  printf '\n'
  ((rc == 0)) && oma_ok "$msg" || oma_err "$msg failed (exit $rc)"
  oma_pause
  return $rc
}

# --- selection ---------------------------------------------------------------

# oma_select <header> <entry...> where each entry is "key<TAB>label<TAB>value".
# Prints the chosen key; non-zero exit means the user backed out with esc/ctrl-c.
oma_select() {
  local header="$1"
  shift
  local -a keys=() lines=()
  local e key lab val maxlab=0

  for e in "$@"; do
    IFS=$'\t' read -r key lab val <<<"$e"
    ((${#lab} > maxlab)) && maxlab=${#lab}
  done
  # printf's %-Ns pads by bytes, so any label containing a multibyte character
  # (›, …, ←) would come up short. Pad by character count instead.
  local pad
  for e in "$@"; do
    IFS=$'\t' read -r key lab val <<<"$e"
    keys+=("$key")
    if [[ -n ${val:-} ]]; then
      pad=$((maxlab - ${#lab}))
      ((pad < 0)) && pad=0
      lines+=("$(printf '%s%*s   %s' "$lab" "$pad" "" "$val")")
    else
      lines+=("$lab")
    fi
  done

  local height=$((${#lines[@]} + 1))
  ((height > 18)) && height=18

  local choice i
  choice=$(printf '%s\n' "${lines[@]}" |
    gum choose --header "$header" --height "$height" --cursor "❯ ") || return 1

  for i in "${!lines[@]}"; do
    [[ ${lines[$i]} == "$choice" ]] && {
      printf '%s' "${keys[$i]}"
      return 0
    }
  done
  return 1
}

# oma_pick <header> <current> <option...> — searchable list, current marked.
oma_pick() {
  local header="$1" current="$2"
  shift 2
  local -a display=()
  local o
  for o in "$@"; do
    [[ $o == "$current" ]] && display+=("● $o") || display+=("  $o")
  done

  local height=$((${#display[@]} + 2))
  ((height > 18)) && height=18

  local choice
  choice=$(printf '%s\n' "${display[@]}" |
    gum filter --header "$header" --height "$height" --placeholder "type to search…" \
      --indicator "❯" --prompt "  ") || return 1
  printf '%s' "${choice:2}"
}

# --- misc --------------------------------------------------------------------

oma_backup() {
  [[ -f $1 ]] || return 0
  cp "$1" "$1.bak.$(date +%s)"
}

oma_bool_label() { [[ $1 == 1 || $1 == true || $1 == yes || $1 == on ]] && printf 'on' || printf 'off'; }

oma_editor() { printf '%s' "${EDITOR:-${VISUAL:-nvim}}"; }

oma_edit_file() {
  local file="$1"
  [[ -f $file ]] || {
    oma_err "no such file: $file"
    oma_pause
    return 1
  }
  local ed
  ed=$(oma_editor)
  oma_has "$ed" || ed=vi
  oma_backup "$file"
  "$ed" "$file" </dev/tty >/dev/tty 2>&1
}
