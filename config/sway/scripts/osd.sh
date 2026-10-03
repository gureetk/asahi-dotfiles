#!/usr/bin/env bash
# Changes volume or brightness and shows a pop-up with the new level,
# like GNOME's. The pop-up is a mako notification, so nothing extra runs
# in the background. Used by the Mac keys and by scrolling on the bar icons.
#
#   osd.sh volume up|down|mute
#   osd.sh brightness up|down|<percent>      e.g. osd.sh brightness 50
#   osd.sh keyboard up|down|toggle           keyboard backlight

sink=@DEFAULT_AUDIO_SINK@
kbd='*kbd_backlight*'

popup() {   # popup <icon> <text> <percent>
    # The text is the summary; the icon goes in the body so it can use the
    # icon font (mako only allows markup in the body).
    notify-send -a osd -u low -t 1500 \
        -h string:x-canonical-private-synchronous:osd \
        -h "int:value:$3" \
        "$2" "<span font_family='Font Awesome 6 Free' font_weight='900'>$1</span>"
}

percent_of() {   # current brightness percent from `brightnessctl -m` output
    cut -d, -f4 | tr -d '%'
}

case "$1" in
    volume)
        case "$2" in
            up)   wpctl set-mute "$sink" 0; wpctl set-volume -l 1.0 "$sink" 5%+ ;;
            down) wpctl set-mute "$sink" 0; wpctl set-volume "$sink" 5%- ;;
            mute) wpctl set-mute "$sink" toggle ;;
        esac
        out=$(wpctl get-volume "$sink")            # "Volume: 0.45" or "Volume: 0.45 [MUTED]"
        level=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$out")
        if [[ "$out" == *MUTED* ]]; then
            popup $'' "Muted" 0
        elif (( level == 0 )); then
            popup $'' "Volume 0%" 0
        elif (( level < 50 )); then
            popup $'' "Volume $level%" "$level"
        else
            popup $'' "Volume $level%" "$level"
        fi
        ;;
    brightness)
        case "$2" in
            up)   brightnessctl -q set 5%+ ;;
            down)
                # Stop at 1% instead of turning the screen fully black
                if (( $(brightnessctl -m | percent_of) <= 6 )); then
                    brightnessctl -q set 1%
                else
                    brightnessctl -q set 5%-
                fi
                ;;
            *[0-9]*) brightnessctl -q set "${2%\%}%" ;;
        esac
        level=$(brightnessctl -m | percent_of)
        popup $'' "Brightness $level%" "$level"
        ;;
    keyboard)
        case "$2" in
            up)   brightnessctl -q -d "$kbd" set 10%+ ;;
            down) brightnessctl -q -d "$kbd" set 10%- ;;
            toggle)
                if (( $(brightnessctl -m -d "$kbd" | percent_of) > 0 )); then
                    brightnessctl -q -d "$kbd" set 0
                else
                    brightnessctl -q -d "$kbd" set 50%
                fi
                ;;
        esac
        level=$(brightnessctl -m -d "$kbd" | percent_of)
        popup $'' "Keyboard light $level%" "$level"
        ;;
    *)
        echo "usage: $0 volume up|down|mute | brightness up|down|N | keyboard up|down|toggle" >&2
        exit 1
        ;;
esac
