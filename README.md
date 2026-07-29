# omasettings

A terminal UI for Omarchy settings — theme, keybindings, displays, audio,
notifications, and the rest, in one menu.

![omasettings](demo/omasettings.gif)

## Install

```bash
omarchy pkg aur add omasettings
```

Or from source:

```bash
git clone https://github.com/joeyvigil/omasettings
cd omasettings && ./install.sh
```

## Usage

```bash
omasettings              # open the menu
omasettings appearance   # jump straight to a section
omasettings search       # search every setting at once
```

Arrows move, `enter` selects, `esc` goes back.

## What it covers

| Section | |
|---|---|
| **Appearance** | theme, font, wallpaper, rounding, opacity, blur |
| **Look & Feel** | gaps, borders, tiling layout, animations |
| **Waybar** | modules, position, height |
| **Keybindings** | browse, search, rebind |
| **Input** | keyboard, mouse, touchpad |
| **Display** | monitors, brightness, night light |
| **Audio** | devices, volume |
| **Network** | Wi-Fi, Bluetooth, DNS |
| **Notifications** | do-not-disturb, timeout, position |
| **Apps & Startup** | default apps, login programs, web apps |
| **Power** | profile, idle, battery, hibernation |
| **System** | updates, security, snapshots, config resets |

Every menu shows each setting's current value beside it. There is also a global
search, a view of everything you have changed from Omarchy's defaults, and a
restore picker for any backup omasettings has taken.

## How it works

Settings Omarchy already has a command for are delegated to `omarchy ...`, so
hooks still fire. The rest are edited directly in `~/.config`, with a writer per
format that preserves comments and layout. Nothing under
`~/.local/share/omarchy/` is ever written to.

Files are backed up before every edit. Hyprland changes are reloaded and checked
with `hyprctl configerrors`, and offered back from the backup if they fail.

## Development

`packaging/` holds the PKGBUILDs and the AUR publishing script. `demo/` holds
the VHS tape and recorder for the GIF above.

MIT
