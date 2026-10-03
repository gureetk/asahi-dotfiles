#!/usr/bin/env bash
# Power & sleep settings: when the screen turns off and when the Mac goes to
# sleep, separately for battery and plugged in. Opened from the quick-settings
# menu. Changes apply right away and are saved in ~/.config/sway/power.conf.

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sway"
conf="$cfg/power.conf"
idle="$cfg/scripts/idle.sh"

declare -A value
load() {
    local key val
    while IFS='=' read -r key val; do value[$key]=$val; done < <("$idle" --settings)
}

minutes() {   # 0 -> Never, 1 -> 1 minute, 15 -> 15 minutes, 60 -> 1 hour
    case "$1" in
        0)  echo "Never" ;;
        1)  echo "1 minute" ;;
        60) echo "1 hour" ;;
        *)  echo "$1 minutes" ;;
    esac
}

save() {
    mkdir -p "$cfg"
    cat > "$conf" <<EOF
# Power & sleep settings, in minutes (0 = never).
# Change them from the quick-settings menu (Power & sleep settings), or edit
# this file and run: ~/.config/sway/scripts/idle.sh --reload

# On battery
screen_off_on_battery=${value[screen_off_on_battery]}
sleep_on_battery=${value[sleep_on_battery]}

# Plugged in
screen_off_plugged_in=${value[screen_off_plugged_in]}
sleep_plugged_in=${value[sleep_plugged_in]}

# Lock the screen when it turns off and before sleeping (yes or no)
lock_screen=${value[lock_screen]}
EOF
    "$idle" --reload
}

keys=(screen_off_on_battery sleep_on_battery screen_off_plugged_in sleep_plugged_in lock_screen)
names=("Screen off on battery" "Sleep on battery" "Screen off when plugged in"
       "Sleep when plugged in" "Lock when the screen turns off")

load
choice=0
while true; do
    labels=()
    for i in "${!keys[@]}"; do
        k=${keys[$i]}
        if [ "$k" = lock_screen ]; then shown=${value[$k]^}; else shown=$(minutes "${value[$k]}"); fi
        labels+=("$(printf '%-32s %s' "${names[$i]}" "$shown")")
    done

    choice=$(printf '%s\n' "${labels[@]}" |
        fuzzel --dmenu --index --no-sort --prompt "Power & sleep ❯ " --width 48 \
               --lines ${#labels[@]} --font monospace:size=11) || exit 0
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice < ${#keys[@]} )) || exit 0
    key=${keys[$choice]}

    if [ "$key" = lock_screen ]; then
        options=(yes no); option_labels=("Yes" "No")
    else
        options=(1 2 3 5 10 15 20 30 45 60 0)
        option_labels=(); for m in "${options[@]}"; do option_labels+=("$(minutes "$m")"); done
    fi

    pick=$(printf '%s\n' "${option_labels[@]}" |
        fuzzel --dmenu --index --no-sort --prompt "${names[$choice]} ❯ " --width 40 \
               --lines ${#option_labels[@]}) || continue
    [[ "$pick" =~ ^[0-9]+$ ]] && (( pick < ${#options[@]} )) || continue

    value[$key]=${options[$pick]}
    save
    notify-send -t 2000 -a power "${names[$choice]}: ${option_labels[$pick]}"
done
