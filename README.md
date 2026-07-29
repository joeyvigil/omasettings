# omasettings

A terminal UI for adjusting Omarchy settings from one menu — appearance, the
status bar, keybindings, input, displays, audio, network, notifications,
startup programs, power, and system configuration.

```
╭──────────────────────────────────────────────────────────────╮
│  󰒓  Omarchy Settings                                         │
╰──────────────────────────────────────────────────────────────╯
What would you like to change?
❯ Search all settings…  type to find anything
  Appearance           theme · font · wallpaper
  Look & Feel          gaps · borders · animations
  Waybar               modules · position · height
  Keybindings          browse · search · rebind
  Input                keyboard · mouse · touchpad
  Display              monitors · brightness · night light
  Audio                devices · volume
  Network              wi-fi · bluetooth · dns
  Notifications        do-not-disturb · timeout · position
  Toggles              waybar · idle · screensaver
  Apps & Startup       defaults · login programs · web apps
  Power                profile · idle · battery
  System               update · security · snapshots
  Changed from defaults  what you have customized
  Restore a backup       undo an earlier change
  Quit
```

Every menu shows the current value next to each setting, so you can read the
state of the system without changing anything.

## Install

From the AUR:

```bash
omarchy pkg aur add omasettings     # or: yay -S omasettings
```

From a clone, for hacking on it:

```bash
git clone https://github.com/joeyvigil/omasettings
cd omasettings && ./install.sh
```

`install.sh` symlinks `bin/omasettings` into `~/.local/bin`, so a `git pull` is
enough to update. Set `BIN_DIR` to link elsewhere.

Requires `omarchy`, [`gum`](https://github.com/charmbracelet/gum), and `jq` —
Omarchy ships all three.

## Why not just `omarchy menu`?

Omarchy already has a settings UI: `omarchy menu`, driven by Walker. omasettings
is the terminal counterpart. It works over SSH and in a TTY, shows the current
value of every setting next to it rather than only on the screen you drill into,
searches across everything at once, and reaches settings that only exist as
lines in a config file — gaps, opacity, keyboard repeat, touchpad tuning,
Waybar modules, monitor layout.

## Usage

```bash
omasettings              # open the menu
omasettings appearance   # jump straight to a section
omasettings search       # go straight to search
omasettings --help
```

Arrow keys move, `enter` selects, `esc` goes back one level.

Sections: `appearance`, `looknfeel`, `waybar`, `keybindings`, `input`,
`display`, `monitors`, `audio`, `network`, `notifications`, `toggles`, `apps`,
`power`, `security`, `system`, plus `search`, `changed`, and `restore`.

## What it changes

| Section | Settings |
|---|---|
| Appearance | Theme, monospace font, wallpaper, corner rounding, window dimming, active/inactive opacity, blur, shadows |
| Look & Feel | Window gaps mode, inner/outer gaps, border size, resize on border, tiling layout, animations, aspect ratio, scrolling column width |
| Waybar | Bar visibility, which modules appear and where, bar position, height, module spacing, `style.css` |
| Keybindings | Browse and search every active binding, rebind, add, remove, list combos running more than one action |
| Input | Keyboard layout/variant/options, repeat rate and delay, numlock, mouse sensitivity and acceleration, focus-follows-mouse, full touchpad submenu |
| Display | Per-monitor resolution, refresh, scale, position, rotation, enable/disable; brightness; night light schedule; lock screen |
| Audio | Default output and input device, volume, mic volume, mute, mixer |
| Network | Wi-Fi and Bluetooth status and controls, Wi-Fi power saving, DNS provider |
| Notifications | Do-not-disturb, dismiss timeout, screen corner, width, height, max visible, border, history |
| Toggles | Waybar, idle lock, night light, screensaver, suspend, do-not-disturb, touchpad, touchscreen, hybrid GPU |
| Apps & Startup | Default browser/editor/terminal, login startup programs, web apps, terminal-app launchers, optional software |
| Power | Power profile, idle timeouts, battery status, hibernation |
| System | Update, timezone, release channel, security (sudo, fingerprint, FIDO2), snapshots, restart components, reset configs, setup wizards, boot screen, debug info |

## How it works

Two kinds of setting sit behind one interface:

- **Things Omarchy already has a command for** (themes, fonts, toggles, default
  apps, snapshots) are delegated to `omarchy ...` so behaviour matches the rest
  of the system, hooks included.
- **Things that only live in config files** (gaps, opacity, keyboard repeat,
  Waybar modules, mako timeouts, monitor layout) are edited directly under
  `~/.config/`.

Nothing under `~/.local/share/omarchy/` is ever written to — that is Omarchy's
own git checkout, and edits there are lost on the next update.

The System menu's restart / refresh / install / setup submenus are generated
from `omarchy commands --json`, so commands added by future Omarchy releases
appear automatically.

### The settings registry

`lib/registry.sh` declares every Hyprland-backed setting in one table — section,
label, file, config section, key, live option, type, choices. Section menus,
global search, and the changed-from-defaults view all read from it, so adding a
line there makes a setting appear in all three at once.

### Editing config files safely

Each format gets a writer that understands it, so comments and layout survive:

- **Hyprland** (`*.conf`) — brace-scoped. Uncomments a setting in place when
  Omarchy left it commented as a hint, creates nested blocks like
  `decoration { blur { … } }`, and drops duplicate assignments that would
  silently win on reload.
- **monitors.conf** — a flat list of `monitor =` lines; the named override for
  one output is replaced in place, leaving Omarchy's wildcard line alone.
- **Waybar** (`config.jsonc`) — patches a single top-level key, whether its
  value is inline or spread over several lines. Depth is tracked with string
  literals blanked out first, because Waybar format strings (`"{icon}"`) would
  otherwise throw off the brace count.
- **mako** — only the global region above the first `[criteria]` block is
  touched; criteria blocks are left alone.
- **autostart.conf** — startup programs are disabled by commenting, not
  deleting, so it is reversible from the same list.

Choosing **Use Omarchy default** (or submitting an empty value) comments the
line back out rather than deleting it.

Every file is backed up to `<file>.bak.<timestamp>` before each edit. After a
Hyprland change the config is reloaded and checked with `hyprctl configerrors`;
if it fails, the errors are shown and you are offered the backup back.
**Restore a backup** on the main menu lists every backup under `~/.config`
newest first, shows a diff, and restores the one you pick — itself backing up
what it replaces.

### When a setting appears to do nothing

Hyprland sources `~/.local/state/omarchy/toggles/hypr/*.conf` *after* your own
config, so an active Omarchy toggle overrides it. The most common case is
no-gaps mode, which pins gaps, border size, and rounding to `0`.

When a value is written but Hyprland keeps reporting a different one,
omasettings says so and names the file responsible instead of leaving you to
wonder. Look & Feel › Window gaps mode turns that particular one off.

## Layout

```
bin/omasettings     entry point, argument handling, main menu
lib/core.sh         theming, prompts, output helpers
lib/hyprconf.sh     Hyprland config read/write, reload, verification
lib/registry.sh     declarative table of Hyprland-backed settings
lib/search.sh       global search, changed-from-defaults, backup restore
lib/*.sh            one file per section
install.sh          symlink onto PATH
```

omasettings reads the palette from `~/.config/omarchy/current/theme/colors.toml`
at startup and re-reads it after a theme change, so it restyles itself
immediately rather than waiting for a new session.

### Notes on the environment

- `hyprctl -j binds` emits malformed JSON in current Hyprland (keys and values
  come out misaligned), so keybindings are parsed from the plain-text output.
- Labels are padded by character count rather than `printf`'s byte-based
  `%-Ns`, which would misalign any row containing `›`, `…`, or `←`.
