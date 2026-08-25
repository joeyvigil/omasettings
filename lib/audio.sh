#!/bin/bash
# Audio: default devices and volume.
#
# Omarchy 3 ships a mixer TUI reached with `omarchy launch audio`; Omarchy 4
# replaced it with a shell panel. Either way this section covers the things you
# would otherwise drop to a shell for.

_audio_sinks() { pactl -f json list sinks 2>/dev/null | jq -r '.[] | "\(.name)\t\(.description)"'; }
_audio_sources() {
  pactl -f json list sources 2>/dev/null |
    jq -r '.[] | select(.monitor_source == null or (.name | endswith(".monitor") | not))
           | "\(.name)\t\(.description)"'
}

_audio_default_sink() { pactl get-default-sink 2>/dev/null; }
_audio_default_source() { pactl get-default-source 2>/dev/null; }

_audio_desc() {
  # Friendly name for a device id, falling back to the id itself.
  local id="$1" name desc
  while IFS=$'\t' read -r name desc; do
    [[ $name == "$id" ]] && {
      printf '%s' "$desc"
      return
    }
  done < <(
    _audio_sinks
    _audio_sources
  )
  printf '%s' "$id"
}

_audio_volume() {
  oma_has wpctl || return 0
  local v muted
  v=$(wpctl get-volume "@DEFAULT_AUDIO_${1:-SINK}@" 2>/dev/null)
  [[ -z $v ]] && return 0
  muted=""
  [[ $v == *MUTED* ]] && muted=" (muted)"
  # "Volume: 0.20" -> "20%"
  v=$(printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+' | head -1)
  [[ -z $v ]] && return 0
  printf '%d%%%s' "$(awk -v x="$v" 'BEGIN{printf "%d", x*100}')" "$muted"
}

_audio_pick_device() {
  local kind="$1" current="$2"
  local -a ids=() labels=()
  local name desc

  while IFS=$'\t' read -r name desc; do
    [[ -z $name ]] && continue
    ids+=("$name")
    labels+=("$desc")
  done < <([[ $kind == sink ]] && _audio_sinks || _audio_sources)

  ((${#ids[@]})) || {
    oma_err "no audio ${kind}s found"
    oma_pause
    return 1
  }

  local current_label
  current_label=$(_audio_desc "$current")

  local pick
  pick=$(oma_pick "Default $([[ $kind == sink ]] && echo output || echo input)" \
    "$current_label" "${labels[@]}") || return 0
  [[ -z $pick ]] && return 0

  local i
  for i in "${!labels[@]}"; do
    if [[ ${labels[$i]} == "$pick" ]]; then
      printf '\n'
      oma_spin "Default $kind set to $pick" pactl "set-default-$kind" "${ids[$i]}"
      sleep 0.4
      return 0
    fi
  done
}

audio_menu() {
  oma_require pactl || {
    oma_err "pactl (PipeWire/PulseAudio tools) is not installed"
    oma_pause
    return 1
  }

  while true; do
    oma_screen "Audio"

    local choice
    choice=$(oma_select "Devices and volume" \
      "$(printf 'output\tOutput device\t%s' "$(_audio_desc "$(_audio_default_sink)")")" \
      "$(printf 'input\tInput device\t%s' "$(_audio_desc "$(_audio_default_source)")")" \
      "$(printf 'volume\tOutput volume\t%s' "$(_audio_volume SINK)")" \
      "$(printf 'micvol\tMicrophone volume\t%s' "$(_audio_volume SOURCE)")" \
      $'mute\tMute / unmute output\t' \
      $'micmute\tMute / unmute microphone\t' \
      $'mixer\tOpen the audio mixer\t' \
      $'restart\tRestart audio (PipeWire)\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    output) _audio_pick_device sink "$(_audio_default_sink)" ;;
    input) _audio_pick_device source "$(_audio_default_source)" ;;
    volume | micvol)
      local target=SINK label="Output volume"
      [[ $choice == micvol ]] && target=SOURCE label="Microphone volume"
      local pct
      pct=$(gum input --header "$label percentage (0–150)" --placeholder "60") || continue
      [[ $pct =~ ^[0-9]+$ ]] || {
        oma_err "not a number"
        oma_pause
        continue
      }
      ((pct > 150)) && pct=150
      printf '\n'
      oma_spin "$label set to $pct%" wpctl set-volume "@DEFAULT_AUDIO_${target}@" "${pct}%"
      sleep 0.4
      ;;
    mute)
      printf '\n'
      oma_spin "Output mute toggled" wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      sleep 0.4
      ;;
    micmute)
      printf '\n'
      oma_spin "Microphone mute toggled" omarchy audio input mute
      sleep 0.4
      ;;
    mixer)
      # shellcheck disable=SC2046  # the mapped command is split on purpose
      $(oma_cmd_line mixer) >/dev/null 2>&1 &
      oma_ok "opened the audio mixer"
      sleep 0.6
      ;;
    restart)
      oma_confirm "Restart audio? Sound will cut out briefly." && {
        # shellcheck disable=SC2046
        oma_exec "Audio restarted" $(oma_cmd_line audio-restart)
      }
      ;;
    back | *) return 0 ;;
    esac
  done
}
