#!/bin/bash
# Record the README demo GIF.
#
#   ./demo/record.sh [output.gif]
#
# The recording drives the real application against the real system, so this
# wrapper notes the one setting the tape changes (corner rounding) and puts it
# back afterwards, whatever happens. It also injects the palette of whichever
# Omarchy theme is active, so the GIF looks like the desktop it came from
# rather than VHS's defaults.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/demo/omasettings.gif}"
TAPE="$ROOT/demo/demo.tape"
COLORS="$HOME/.config/omarchy/current/theme/colors.toml"

command -v vhs >/dev/null || {
  echo "vhs is not installed. Install it with:" >&2
  echo "    omarchy pkg add vhs" >&2
  exit 1
}

# Reuse the application's own config reader/writer rather than a second,
# untested copy of the same logic.
# shellcheck source=../lib/core.sh
source "$ROOT/lib/core.sh"
# shellcheck source=../lib/hyprconf.sh
source "$ROOT/lib/hyprconf.sh"

TMP_TAPE=""
BEFORE=$(hypr_get "$OMA_LOOKNFEEL" decoration rounding)

restore() {
  local rc=$?
  [[ -n $TMP_TAPE ]] && rm -f "$TMP_TAPE"

  if [[ -n $BEFORE ]]; then
    hypr_set "$OMA_LOOKNFEEL" decoration rounding "$BEFORE"
    echo "==> restored corner rounding to $BEFORE"
  else
    # It was not set before, so the tape's edit must be taken back out.
    hypr_unset "$OMA_LOOKNFEEL" decoration rounding
    echo "==> reverted corner rounding to the Omarchy default"
  fi
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true

  # Clear the backups the recording generated so they do not accumulate.
  find "$HOME/.config/hypr" -name 'looknfeel.conf.bak.*' -newermt '-15 minutes' \
    -delete 2>/dev/null || true
  exit $rc
}
trap restore EXIT

echo "==> corner rounding is currently ${BEFORE:-unset}; it will be restored"

# --- build the tape with the live theme --------------------------------------

theme=$(python3 - "$COLORS" <<'PY'
import re, sys, json
try:
    s = open(sys.argv[1]).read()
except OSError:
    sys.exit(1)
def g(k):
    m = re.search(rf'^{k}\s*=\s*"([^"]*)"', s, re.M)
    return m.group(1) if m else None
names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
t = {"background": g("background"), "foreground": g("foreground"),
     "cursor": g("cursor"), "selection": g("selection_background")}
for i, n in enumerate(names):
    t[n] = g(f"color{i}")
    t["bright" + n.capitalize()] = g(f"color{i + 8}")
if not all(t.values()):
    sys.exit(1)
print(json.dumps(t))
PY
) || theme=""

TMP_TAPE=$(mktemp --suffix=.tape)
{
  # VHS's parser splits an unquoted path on its slashes.
  printf 'Output "%s"\n' "$OUT"
  [[ -n $theme ]] && printf 'Set Theme %s\n' "$theme"
  cat "$TAPE"
} >"$TMP_TAPE"

mkdir -p "$(dirname "$OUT")"
echo "==> recording the $(omarchy theme current 2>/dev/null) theme into $(basename "$OUT")"
vhs "$TMP_TAPE"

if command -v gifsicle >/dev/null; then
  echo "==> optimising"
  gifsicle -O3 --lossy=50 -o "$OUT" "$OUT" 2>/dev/null || true
fi

printf '==> %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
