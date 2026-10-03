#!/usr/bin/env bash
# Set the desktop wallpaper. It stays after reloads and reboots.
#
#   wallpaper.sh                     pick an image (Ctrl+Shift+W does this)
#   wallpaper.sh ~/Downloads/x.jpg   use that image
#   wallpaper.sh ~/x.jpg fit         fill (default), fit, center, tile or stretch
#   wallpaper.sh none                back to the plain dark background
#
# The picker lists JPG/PNG images in ~/Pictures (put yours in
# ~/Pictures/Wallpapers) and Fedora's built-in ones in /usr/share/backgrounds.

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sway"
conf="$cfg/wallpaper.conf"      # included by the sway config
plain='#16161e'

if [ $# -eq 0 ]; then
    pick=$(find "$HOME/Pictures" /usr/share/backgrounds -maxdepth 3 -type f \
               \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
               -not -path '*/Screenshots/*' 2>/dev/null |
           sort | sed -e "s|^$HOME/|~/|" -e "s|^/usr/share/backgrounds/|Fedora: |" |
           fuzzel --dmenu --prompt "Wallpaper ❯ " --width 44) || exit 0
    case "$pick" in
        "~/"*)      pick="$HOME/${pick#\~/}" ;;
        "Fedora: "*) pick="/usr/share/backgrounds/${pick#Fedora: }" ;;
    esac
    set -- "$pick"
fi

image="$1"
mode="${2:-fill}"

if [ "$image" = "none" ]; then
    echo "output * bg $plain solid_color" > "$conf"
    swaymsg "output * bg $plain solid_color" >/dev/null
    exit 0
fi

if [ ! -f "$image" ]; then
    notify-send "Wallpaper" "Can't find $image"
    exit 1
fi

case "$mode" in
    fill|fit|center|tile|stretch) ;;
    *) echo "mode must be fill, fit, center, tile or stretch" >&2; exit 1 ;;
esac

# Keep a copy, so the wallpaper survives if the original is moved or deleted
ext="${image##*.}"
saved="$cfg/wallpaper.${ext,,}"
if [ "$(realpath "$image")" != "$(realpath -m "$saved")" ]; then
    rm -f "$cfg"/wallpaper.jpg "$cfg"/wallpaper.jpeg "$cfg"/wallpaper.png
    cp -f "$image" "$saved"
fi

echo "output * bg \"$saved\" $mode" > "$conf"
swaymsg "output * bg \"$saved\" $mode" >/dev/null
