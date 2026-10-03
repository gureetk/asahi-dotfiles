#!/usr/bin/env bash
# Searchable shortcut list. Bound to Ctrl+? (Ctrl+Shift+/) and Ctrl+/.
# Type to filter, Esc to close. Edit the list in ~/.config/sway/keybinds.txt.

list="${XDG_CONFIG_HOME:-$HOME/.config}/sway/keybinds.txt"

# Pressing the shortcut again closes the list
pkill -x fuzzel && exit 0

fuzzel --dmenu --font monospace:size=11 --prompt "Shortcuts ❯ " \
    --width 78 --lines 20 < "$list" >/dev/null
