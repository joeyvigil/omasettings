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

1. **Cut a release** so `source=` has something to download:

   ```bash
   git tag -a v1.0.0 -m "omasettings 1.0.0"
   git push origin v1.0.0
   ```

2. **Replace `SKIP` with a real checksum.** `SKIP` is fine while iterating but
   should not ship — it disables integrity checking for everyone installing.

   ```bash
   updpkgsums PKGBUILD     # from pacman-contrib
   ```

3. **Add an SSH key to your AUR account** at
   <https://aur.archlinux.org/account/> (Account → SSH Public Key).

4. **Clone the empty AUR repo and push:**

   ```bash
   git clone ssh://aur@aur.archlinux.org/omasettings.git aur-omasettings
   cd aur-omasettings
   cp ../packaging/PKGBUILD .
   makepkg --printsrcinfo > .SRCINFO   # required; the AUR rejects pushes without it
   git add PKGBUILD .SRCINFO
   git commit -m "Initial release: omasettings 1.0.0"
   git push
   ```

`.SRCINFO` has to be regenerated and committed on every version bump, or the
AUR web view will show stale metadata.

## Notes on dependencies

`omarchy` is listed under `optdepends` rather than `depends`. The tool is not
useful without it, but Omarchy is normally installed by its own bootstrap
script into `~/.local/share/omarchy` rather than as a pacman package, so a hard
dependency would fail for most of the people who actually want this. The
wrapper checks for `omarchy` on `PATH` at startup and exits with an explanation
if it is missing.
