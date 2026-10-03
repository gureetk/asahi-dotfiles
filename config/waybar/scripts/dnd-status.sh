#!/usr/bin/env bash
# Shows a muted-bell icon in the bar while Do Not Disturb is on; hidden otherwise.

if makoctl mode 2>/dev/null | grep -qx do-not-disturb; then
    printf '%s\n' '{"text": "", "tooltip": "Do Not Disturb is on (click to turn off)", "class": "on"}'
else
    printf '%s\n' '{"text": ""}'
fi
