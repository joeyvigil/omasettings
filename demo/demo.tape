# VHS tape for the README demo. Rendered by demo/record.sh, which injects the
# current Omarchy theme's palette above this file and restores any setting the
# recording changes afterwards.
#
#   ./demo/record.sh
#
# Do not run `vhs demo/demo.tape` directly: it would record in VHS's default
# colours and leave the corner-rounding change applied.
#
# Two things govern the key counts below, and both are easy to get wrong:
#
#   * gum redraws each menu from scratch, so the cursor is back on the first
#     row every time you return to one. Never assume it stayed where it was —
#     and note that Up from the first row wraps to the last (Quit).
#   * The theme list is alphabetical, and the first six installed themes here
#     ship no preview.png. The Down counts land on stock themes that do, so
#     the preview pane actually shows something.

Set Shell bash
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 15
Set Width 1020
Set Height 660
Set Padding 24
Set TypingSpeed 55ms
Set Framerate 20
Set PlaybackSpeed 1.0

# VHS's shell does not necessarily source the user's profile, so put the
# install location on PATH explicitly before anything is recorded.
Hide
Type "export PATH=$HOME/.local/bin:/usr/bin:$PATH; clear" Enter
Sleep 500ms
Show

Sleep 700ms
Type "omasettings" Sleep 400ms Enter

# --- the main menu -----------------------------------------------------------
Sleep 2.5s

# --- Appearance --------------------------------------------------------------
Down Sleep 800ms
Enter Sleep 2s

# --- the theme picker, with live previews ------------------------------------
# Cursor opens on Aether (row 1). Each hop lands on a stock theme with artwork.
Enter Sleep 2.8s
Down @110ms 6 Sleep 2.2s
Down @110ms 7 Sleep 2.2s
Down @110ms 6 Sleep 2.2s
Down @110ms 8 Sleep 2.4s
Escape Sleep 1.6s

# --- change a setting --------------------------------------------------------
# Back in Appearance, cursor reset to Theme; Corner rounding is three rows down.
Down @180ms 3 Sleep 1.1s
Enter Sleep 1.6s
Backspace @120ms 4 Sleep 400ms
Type "14" Sleep 700ms
Enter Sleep 2.6s
Sleep 1.4s

# --- search across everything ------------------------------------------------
# Escape lands on the main menu with the cursor on row 1, which is Search.
Escape Sleep 1.3s
Enter Sleep 1.6s
Type "gaps" Sleep 2.6s
Escape Sleep 2.5s
