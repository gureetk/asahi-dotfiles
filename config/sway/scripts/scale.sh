#!/usr/bin/env bash
# Display scale: how big everything on the screen is. Opened from the
# quick-settings menu (Display scale…). Changes apply right away and are
# saved in ~/.config/sway/scale.conf, which the installer never overwrites.
#
#   scale.sh               pick a size
#   scale.sh 1.75          set it directly (1 = smallest, 2 = twice as big; 175% works too)
#   scale.sh --login       pick the login screen's text size
#   scale.sh --login 150%  set it directly (asks for your password)
#
# The login screen (tuigreet) runs on the text console, so its size comes
# from the console font in /etc/vconsole.conf, not from sway. A new login
# text size shows from the next restart.

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sway"
conf="$cfg/scale.conf"      # included by the sway config
default=1.5
sizes=(1 1.25 1.5 1.75 2)
fonts="${CONSOLE_FONT_DIR:-/usr/lib/kbd/consolefonts}"
vconsole="${VCONSOLE_CONF:-/etc/vconsole.conf}"

percent() { awk -v s="$1" 'BEGIN { printf "%d%%", s * 100 + 0.5 }'; }
same()    { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; exit !(d < 0.01 && d > -0.01) }'; }

# "150%" or "1.5" -> 1.5; fails if it isn't a sensible scale
parse() {
    local v=${1%\%}
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    [[ "$1" == *% ]] && v=$(awk -v p="$v" 'BEGIN { print p / 100 }')
    awk -v s="$v" 'BEGIN { exit !(s >= 0.5 && s <= 4) }' || return 1
    echo "$v"
}

current_scale() {   # of the first screen that's on
    swaymsg -t get_outputs 2>/dev/null |
        sed -n 's/.*"scale": *\([0-9.]*\).*/\1/p' | awk '$1 > 0 { print; exit }'
}

set_scale() {
    if ! swaymsg "output * scale $1" >/dev/null; then
        notify-send "Display scale" "sway didn't accept $1"
        return 1
    fi
    mkdir -p "$cfg"
    cat > "$conf" <<EOF
# Display scale, set from the quick-settings menu (Display scale).
# 1 = smallest, 2 = everything twice as big. Delete this file to go back to
# the default in ~/.config/sway/config.
output * scale $1
EOF
    notify-send -t 2000 "Display scale: $(percent "$1")"
}

# Login screen text ###########################################################

# Console text height in pixels for a scale: 1 -> 16, 1.5 -> 24, 2 -> 32
height() { awk -v s="$1" 'BEGIN { h = int(s * 4 + 0.5) * 4; if (h < 16) h = 16; if (h > 32) h = 32; print h }'; }

# Terminus console font for a text height. The file names differ between
# Terminus versions (ter-v24n, ter-u24n, ter-124n...), so take what's there.
console_font() {
    local f name
    for f in "$fonts"/ter-{v,u,i,1}"$1"n.psf*; do
        if [ -e "$f" ]; then
            name=${f##*/}
            echo "${name%%.*}"
            return 0
        fi
    done
    return 1
}

current_login() {   # text height of the console font now set, if it's Terminus
    sed -n 's/^FONT="\{0,1\}ter-.\([0-9][0-9]\)[nb].*/\1/p' "$vconsole" 2>/dev/null | tail -1
}

set_login() {
    local font
    if ! font=$(console_font "$(height "$1")"); then
        notify-send "Login screen text" \
            "Needs the Terminus console fonts. Install them with: sudo dnf install terminus-fonts-console"
        return 1
    fi
    if ! command -v pkexec >/dev/null; then
        notify-send "Login screen text" "Can't ask for your password (pkexec is missing)"
        return 1
    fi
    # Runs as root after you type your password. The font name is passed as
    # an argument rather than pasted into the commands.
    if pkexec /bin/sh -c '
        f="$2"
        touch "$f" || exit 1
        if grep -q "^FONT=" "$f"; then
            sed -i "s/^FONT=.*/FONT=\"$1\"/" "$f"
        else
            echo "FONT=\"$1\"" >> "$f"
        fi' sh "$font" "$vconsole"; then
        notify-send -t 5000 "Login screen text: $(percent "$1")" "You'll see it from the next restart."
    fi
}

# Menus #######################################################################

pick() {   # prompt, labels... -> index of the chosen label
    local prompt=$1; shift
    printf '%s\n' "$@" |
        fuzzel --dmenu --index --no-sort --prompt "$prompt ❯ " --width 34 --lines $#
}

display_menu() {
    local now s label labels=() choice
    now=$(current_scale)
    for s in "${sizes[@]}"; do
        label=$(percent "$s")
        same "$s" "$default" && label+="  (default)"
        [ -n "$now" ] && same "$s" "$now" && label+="  ✓"
        labels+=("$label")
    done
    labels+=("Login screen text size…")

    choice=$(pick "Display scale" "${labels[@]}") || exit 0
    [[ "$choice" =~ ^[0-9]+$ ]] || exit 0
    if (( choice < ${#sizes[@]} )); then
        set_scale "${sizes[$choice]}"
    elif (( choice == ${#sizes[@]} )); then
        login_menu
    fi
}

login_menu() {
    local now s label labels=() choice
    now=$(current_login)
    for s in "${sizes[@]}"; do
        label=$(percent "$s")
        [ "$(height "$s")" = "$now" ] && label+="  ✓"
        labels+=("$label")
    done

    choice=$(pick "Login screen text" "${labels[@]}") || exit 0
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice < ${#sizes[@]} )) || exit 0
    set_login "${sizes[$choice]}"
}

usage() { sed -n '6,9p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
    "")        display_menu ;;
    --login)   if [ -n "${2:-}" ]; then
                   s=$(parse "$2") || { usage >&2; exit 1; }
                   set_login "$s"
               else
                   login_menu
               fi ;;
    -h|--help) usage ;;
    *)         s=$(parse "$1") || { usage >&2; exit 1; }
               set_scale "$s" ;;
esac
