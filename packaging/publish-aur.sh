#!/bin/bash
# Publish omasettings to the AUR.
#
# Works for the first submission and for every update after it. Run it from
# anywhere; it clones the AUR repo as a *sibling* of this checkout, never
# inside it, so the two git repos never nest.
#
#   ./packaging/publish-aur.sh            # publish omasettings
#   ./packaging/publish-aur.sh --git      # publish omasettings-git instead
#   ./packaging/publish-aur.sh --no-build # skip the pre-flight build

set -euo pipefail

VARIANT=release
BUILD_CHECK=1
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
  --git) VARIANT=git ;;
  --no-build) BUILD_CHECK=0 ;;
  --yes | -y) ASSUME_YES=1 ;;
  -h | --help)
    sed -n '2,12p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *)
    echo "unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $VARIANT == git ]]; then
  PKGNAME=omasettings-git
  PKGBUILD_SRC="$REPO_ROOT/packaging/PKGBUILD-git"
else
  PKGNAME=omasettings
  PKGBUILD_SRC="$REPO_ROOT/packaging/PKGBUILD"
fi

AUR_DIR="$(dirname "$REPO_ROOT")/aur-$PKGNAME"

say() { printf '\n\033[1m==>\033[0m %s\n' "$*"; }
die() {
  printf '\n\033[31m==> %s\033[0m\n' "$*" >&2
  exit 1
}

# --- pre-flight --------------------------------------------------------------

say "Checking prerequisites"
for c in git makepkg ssh; do
  command -v "$c" >/dev/null || die "$c is not installed"
done
[[ -f $PKGBUILD_SRC ]] || die "no PKGBUILD at $PKGBUILD_SRC"

if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  aur@aur.archlinux.org help 2>&1 | grep -qi 'interactive shell\|Welcome\|help'; then
  cat >&2 <<EOF

The AUR rejected your SSH key, so nothing can be pushed yet.

  1. Register at https://aur.archlinux.org/register
  2. Go to My Account and paste this into "SSH Public Key":

$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo '     (no key at ~/.ssh/id_ed25519.pub — generate one with ssh-keygen -t ed25519)')

  3. Run this script again.

EOF
  exit 1
fi
echo "    AUR SSH access OK"

if ((BUILD_CHECK)); then
  say "Building once to confirm the PKGBUILD works"
  BUILD_TMP=$(mktemp -d)
  trap 'rm -rf "$BUILD_TMP"' EXIT
  cp "$PKGBUILD_SRC" "$BUILD_TMP/PKGBUILD"
  (cd "$BUILD_TMP" && makepkg -f --nodeps >/dev/null 2>&1) ||
    die "the package failed to build — fix that before publishing"
  echo "    build OK"
fi

# --- sync the AUR repo -------------------------------------------------------

if [[ -d $AUR_DIR/.git ]]; then
  say "Updating existing AUR checkout at $AUR_DIR"
  git -C "$AUR_DIR" pull --ff-only origin master 2>/dev/null || true
else
  say "Cloning the AUR repo to $AUR_DIR"
  git clone "ssh://aur@aur.archlinux.org/$PKGNAME.git" "$AUR_DIR"
fi

# The AUR only accepts pushes to master; a fresh clone of an empty repo takes
# its branch name from init.defaultBranch, which is not master everywhere.
current_branch=$(git -C "$AUR_DIR" branch --show-current 2>/dev/null || echo "")
if [[ -z $current_branch ]]; then
  git -C "$AUR_DIR" checkout -q -b master
elif [[ $current_branch != master ]]; then
  say "Renaming branch '$current_branch' to master (the AUR requires it)"
  git -C "$AUR_DIR" branch -m "$current_branch" master
fi

# --- stage -------------------------------------------------------------------

say "Generating PKGBUILD and .SRCINFO"
cp "$PKGBUILD_SRC" "$AUR_DIR/PKGBUILD"
(cd "$AUR_DIR" && makepkg --printsrcinfo >.SRCINFO)

cd "$AUR_DIR"
git add PKGBUILD .SRCINFO

if git diff --cached --quiet; then
  say "Nothing changed — the AUR is already up to date"
  exit 0
fi

version=$(awk -F' = ' '/^\tpkgver = /{print $2}' .SRCINFO)
rel=$(awk -F' = ' '/^\tpkgrel = /{print $2}' .SRCINFO)

say "About to publish $PKGNAME $version-$rel"
git diff --cached --stat
echo
git -c color.ui=always diff --cached | head -60

cat <<EOF

This pushes to the AUR, where it becomes publicly installable straight away.
Removing a package afterwards requires asking a Package Maintainer.

EOF
if ((ASSUME_YES)); then
  reply=y
elif [[ ! -t 0 ]]; then
  # bash only prints a read prompt on a terminal, and git clone's ssh will have
  # eaten anything piped in, so refuse rather than appear to hang or abort
  # for no visible reason.
  echo "Not running interactively. Re-run with --yes to publish." >&2
  exit 1
else
  # read returns non-zero at EOF; without the guard, set -e would kill the
  # script here with no explanation.
  read -rp "Push to the AUR? [y/N] " reply || reply=""
fi

[[ $reply == [yY] ]] || {
  echo "Aborted. Nothing was pushed; the staged files are still in $AUR_DIR"
  exit 0
}

git commit -qm "$PKGNAME $version-$rel"
git push origin master

say "Published: https://aur.archlinux.org/packages/$PKGNAME"
echo "    Install with: omarchy pkg aur add $PKGNAME"
