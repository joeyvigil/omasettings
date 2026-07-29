#!/bin/bash
# Link omasettings onto PATH. Symlinks rather than copies, so `git pull` in this
# checkout is all it takes to update.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TARGET="$BIN_DIR/omasettings"

mkdir -p "$BIN_DIR"
chmod +x "$ROOT/bin/omasettings"

if [[ -e $TARGET && ! -L $TARGET ]]; then
  echo "install: $TARGET exists and is not a symlink; leaving it alone." >&2
  exit 1
fi

ln -sfn "$ROOT/bin/omasettings" "$TARGET"
echo "Linked $TARGET -> $ROOT/bin/omasettings"

missing=()
for c in gum jq omarchy; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if ((${#missing[@]})); then
  echo
  echo "Warning: missing required command(s): ${missing[*]}"
  echo "Install them with: sudo pacman -S ${missing[*]}"
fi

case ":$PATH:" in
*":$BIN_DIR:"*) echo "Run it with: omasettings" ;;
*)
  echo
  echo "$BIN_DIR is not on your PATH. Add this to your shell config:"
  echo "  export PATH=\"\$PATH:$BIN_DIR\""
  ;;
esac
