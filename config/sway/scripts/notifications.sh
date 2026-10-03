#!/usr/bin/env bash
# Recent notifications, newest first. Opened by clicking the clock.
# The first entry brings a dismissed pop-up back on screen.

# `makoctl history` prints "Notification <id>: <summary>" followed by
# "  App name: <app>". IDs go up over time, so sort by them for newest first.
recent=$(makoctl history 2>/dev/null | awk '
    /^Notification [0-9]+:/ {
        if (have) print id "\t" line
        id = $2 + 0
        summary = $0; sub(/^Notification [0-9]+:[ ]?/, "", summary)
        line = summary; have = 1; next
    }
    /^  App name: / {
        app = substr($0, 13)
        if (app != "" && app != "notify-send") line = app "  —  " summary
    }
    END { if (have) print id "\t" line }' | sort -t$'\t' -k1,1nr | cut -f2-)

if [ -z "$recent" ]; then
    notify-send -t 2000 "No recent notifications"
    exit 0
fi

count=$(( $(printf '%s\n' "$recent" | wc -l) + 1 ))
choice=$( { echo "↺  Bring back a dismissed pop-up"; printf '%s\n' "$recent"; } |
          fuzzel --dmenu --index --no-sort --prompt "Notifications ❯ " --width 50 \
                 --lines "$(( count < 12 ? count : 12 ))") || exit 0
[ "$choice" = 0 ] && makoctl restore
