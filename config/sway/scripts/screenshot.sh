#!/usr/bin/env bash
# Usage: screenshot.sh area|full
# Saves to ~/Pictures/Screenshots, copies to the clipboard, shows a notification.

pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
dir="$pictures/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

case "${1:-area}" in
    area)
        geometry=$(slurp) || exit 0   # Esc cancels
        grim -g "$geometry" "$file"
        ;;
    full)
        grim "$file"
        ;;
    *)
        echo "usage: $0 area|full" >&2
        exit 1
        ;;
esac

wl-copy --type image/png < "$file"
notify-send -t 3000 -i "$file" "Screenshot saved" "Copied to clipboard"
