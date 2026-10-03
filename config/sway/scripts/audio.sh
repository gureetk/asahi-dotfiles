#!/usr/bin/env bash
# Pick where sound plays (speakers, headphones, Bluetooth...) or which
# microphone is used. Opened from the volume icon's menu in the bar.
#
#   audio.sh output    choose the output device
#   audio.sh input     choose the microphone

kind="${1:-output}"
case "$kind" in
    output) section="Sinks:";   prompt="Sound output ❯ " ;;
    input)  section="Sources:"; prompt="Microphone ❯ " ;;
    *) echo "usage: $0 output|input" >&2; exit 1 ;;
esac

# Read the devices from `wpctl status`, under "Audio" only.
# Lines look like " │  *   58. Built-in Audio Speakers   [vol: 0.50]"
# where * marks the current default. Prints "<1/0>\t<id>\t<name>".
devices=$(wpctl status | awk -v section="$section" '
    /^Audio/                 { audio = 1; next }
    /^[A-Za-z]/              { audio = 0 }
    audio && index($0, section) { inside = 1; next }
    inside && /(├─|└─)/      { inside = 0 }
    inside && match($0, /[0-9]+\. /) {
        prefix = substr($0, 1, RSTART - 1)
        id     = substr($0, RSTART, RLENGTH - 2)
        name   = substr($0, RSTART + RLENGTH)
        sub(/[ \t]*\[vol:.*$/, "", name)
        sub(/[ \t]+$/, "", name)
        print (index(prefix, "*") ? 1 : 0) "\t" id "\t" name
    }')

if [ -z "$devices" ]; then
    notify-send -t 3000 "No audio devices found"
    exit 0
fi

ids=() names=() labels=()
while IFS=$'\t' read -r is_default id name; do
    ids+=("$id"); names+=("$name")
    if [ "$is_default" = 1 ]; then labels+=("●  $name"); else labels+=("    $name"); fi
done <<< "$devices"

idx=$(printf '%s\n' "${labels[@]}" |
      fuzzel --dmenu --index --no-sort --prompt "$prompt" --width 44 \
                   --lines "$(( ${#labels[@]} < 12 ? ${#labels[@]} : 12 ))") || exit 0
[[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#ids[@]} )) || exit 0

wpctl set-default "${ids[$idx]}"
notify-send -t 2000 -a audio "Now using ${names[$idx]}"
