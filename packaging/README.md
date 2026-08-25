# Packaging

Two PKGBUILDs:

- `PKGBUILD` — builds from a tagged GitHub release. Publish as **`omasettings`**.
- `PKGBUILD-git` — builds from the tip of `main`. Publish as **`omasettings-git`**.

Both install the wrapper to `/usr/share/omasettings/bin/` with the libraries
beside it, and symlink `/usr/bin/omasettings` at it. The wrapper resolves its
own real path through symlinks, so it finds `lib/` either way — the same
mechanism `install.sh` relies on for a clone.

## Build and test locally

```bash
cd packaging
makepkg -f                       # builds the release PKGBUILD
namcap omasettings-*.pkg.tar.zst # optional lint
sudo pacman -U omasettings-*.pkg.tar.zst
```

To test without a published tag, stage a tarball shaped like GitHub's archive
and point `source=` at it:

```bash
mkdir -p /tmp/b/omasettings-1.0.0
cp -r ../bin ../lib ../install.sh ../README.md ../LICENSE /tmp/b/omasettings-1.0.0/
tar -czf /tmp/b/omasettings-1.0.0.tar.gz -C /tmp/b omasettings-1.0.0
sed 's|^source=.*|source=("omasettings-1.0.0.tar.gz")|' PKGBUILD > /tmp/b/PKGBUILD
cd /tmp/b && makepkg -f --nodeps
```

## Publishing to the AUR

One prerequisite, which needs a browser:

1. Register at <https://aur.archlinux.org/register>.
2. Under **My Account → SSH Public Key**, paste `~/.ssh/id_ed25519.pub`.

Then:

```bash
./packaging/publish-aur.sh          # omasettings
./packaging/publish-aur.sh --git    # omasettings-git
```

The script checks your AUR SSH access first and tells you exactly what to do if
it fails, builds the package once to confirm the PKGBUILD works, clones the AUR
repo, regenerates `.SRCINFO`, shows the diff, and asks before pushing. Re-run it
for every update — it is idempotent and exits quietly when nothing changed.

### If you prefer to do it by hand

Three things trip people up:

- **Clone as a sibling of this checkout, not inside it.** Cloning the AUR repo
  into the project directory nests one git repo inside another.
- **`.SRCINFO` must be in the commit.** The AUR rejects pushes without it, and
  serves stale metadata if you change the PKGBUILD without regenerating it.
- **The AUR only accepts the `master` branch.** A fresh clone of an empty repo
  takes its name from `init.defaultBranch`, which is `main` on many setups.

```bash
cd ~/Projects                                   # NOT inside the omasettings repo
git clone ssh://aur@aur.archlinux.org/omasettings.git aur-omasettings
cd aur-omasettings
git branch -m master 2>/dev/null || true        # AUR requires master
cp ../omasettings/packaging/PKGBUILD .
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -m "omasettings 1.0.0-1"
git push origin master
```

### Cutting a new version

Tag first: `updpkgsums` downloads the release tarball, so the tag has to exist
before the checksum can be filled in.

```bash
# bump pkgver in packaging/PKGBUILD, then:
git tag -a v2.0.0 -m "omasettings 2.0.0" && git push origin v2.0.0
updpkgsums packaging/PKGBUILD                   # from pacman-contrib
git commit -am "Release 2.0.0" && git push
./packaging/publish-aur.sh
```

Bump `pkgrel` instead of `pkgver` when only the packaging changed.

## Notes on dependencies

`omarchy` is listed under `optdepends` rather than `depends`. The tool is not
useful without it, but Omarchy 3 is installed by its own bootstrap script into
`~/.local/share/omarchy` rather than as a pacman package, so a hard dependency
would fail for those users. (Omarchy 4 does ship as a package under
`/usr/share/omarchy`.) The wrapper checks for `omarchy` on `PATH` at startup and
exits with an explanation if it is missing.

`waybar` and `mako` are only used on Omarchy 3; Omarchy 4 replaced both with the
Quickshell-based Omarchy shell, which comes with Omarchy itself.
