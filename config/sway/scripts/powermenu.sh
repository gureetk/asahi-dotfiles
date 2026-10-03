#!/usr/bin/env bash
# Power menu shown with fuzzel. Bound to Ctrl+Shift+E.

choice=$(printf '%s\n' "Lock" "Suspend" "Log out" "Reboot" "Shut down" |
    fuzzel --dmenu --prompt "Power ❯ " --lines 5 --width 18) || exit 0

case "$choice" in
    "Lock")      ~/.config/sway/scripts/lock.sh ;;
    "Suspend")   systemctl suspend ;;   # swayidle locks before sleeping
    "Log out")   swaymsg exit ;;
    "Reboot")    systemctl reboot ;;
    "Shut down") systemctl poweroff ;;
esac
