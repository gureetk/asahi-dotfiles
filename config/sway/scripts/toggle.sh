#!/usr/bin/env bash
# Usage: toggle.sh wifi|bluetooth|dnd
# Used by the quick-settings menu in the bar and by Ctrl+N (Do Not Disturb).

case "$1" in
    wifi)
        if [ "$(nmcli radio wifi)" = "enabled" ]; then
            nmcli radio wifi off
            notify-send -t 2000 "Wi-Fi off"
        else
            nmcli radio wifi on
            notify-send -t 2000 "Wi-Fi on"
        fi
        ;;
    bluetooth)
        if bluetoothctl show | grep -q "Powered: yes"; then
            bluetoothctl power off >/dev/null
            notify-send -t 2000 "Bluetooth off"
        else
            rfkill unblock bluetooth 2>/dev/null
            bluetoothctl power on >/dev/null
            notify-send -t 2000 "Bluetooth on"
        fi
        ;;
    dnd)
        if makoctl mode | grep -qx do-not-disturb; then
            makoctl mode -r do-not-disturb >/dev/null
            notify-send -t 2000 "Notifications on"
        else
            makoctl mode -a do-not-disturb >/dev/null
        fi
        # Refresh the bell icon in the bar
        pkill -RTMIN+8 waybar
        ;;
    *)
        echo "usage: $0 wifi|bluetooth|dnd" >&2
        exit 1
        ;;
esac
