#!/usr/bin/env bash
# Screen-off, lock and auto-sleep timers, with separate settings for battery
# and plugged in. Runs swayidle with the right timers and restarts it when you
# plug in, unplug, or change the settings (Power & sleep settings in the
# quick-settings menu, or ~/.config/sway/power.conf).
#
#   idle.sh            start (sway runs this at login)
#   idle.sh --reload   apply changed settings right away
#   idle.sh --status   print the settings in use right now
#   idle.sh --settings print every setting as key=value

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sway"
conf="$cfg/power.conf"
scripts="$cfg/scripts"
pidfile="${XDG_RUNTIME_DIR:-/tmp}/sway-idle.pid"

# Defaults, in minutes (0 = never). power.conf overrides them.
declare -A default=(
    [screen_off_on_battery]=5
    [sleep_on_battery]=15
    [screen_off_plugged_in]=10
    [sleep_plugged_in]=0
    [lock_screen]=yes
)
declare -A setting

read_settings() {
    local key value
    for key in "${!default[@]}"; do setting[$key]=${default[$key]}; done
    [ -f "$conf" ] || return
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"; value="${value//[[:space:]]/}"
        [[ -n "${default[$key]+x}" ]] || continue          # unknown key
        if [ "$key" = lock_screen ]; then
            [[ "$value" =~ ^(yes|no)$ ]] && setting[$key]=$value
        else
            [[ "$value" =~ ^[0-9]+$ ]] && setting[$key]=$value
        fi
    done < <(grep -v '^[[:space:]]*#' "$conf")
}

# "battery" if running on battery, otherwise "plugged" (also on Macs with no battery)
power_source() {
    local status
    for status in "${POWER_SUPPLY_DIR:-/sys/class/power_supply}"/*/status; do
        [ -f "$status" ] || continue
        [ "$(cat "${status%/status}/type" 2>/dev/null)" = Battery ] || continue
        [ "$(cat "$status")" = Discharging ] && { echo battery; return; }
    done
    echo plugged
}

timers() {   # prints "<screen off minutes> <sleep minutes>" for the power source
    if [ "$1" = battery ]; then
        echo "${setting[screen_off_on_battery]} ${setting[sleep_on_battery]}"
    else
        echo "${setting[screen_off_plugged_in]} ${setting[sleep_plugged_in]}"
    fi
}

case "$1" in
    --reload)
        kill -USR1 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
        exit 0
        ;;
    --settings)    # effective settings as key=value (used by power-settings.sh)
        read_settings
        for key in screen_off_on_battery sleep_on_battery screen_off_plugged_in \
                   sleep_plugged_in lock_screen; do
            echo "$key=${setting[$key]}"
        done
        exit 0
        ;;
    --status)
        read_settings
        source=$(power_source)
        read -r off sleep <<< "$(timers "$source")"
        echo "Power: $source. Screen off: ${off:-0} min. Sleep: ${sleep:-0} min (0 = never). Lock: ${setting[lock_screen]}."
        exit 0
        ;;
esac

echo $$ > "$pidfile"
idle_pid=""

start_swayidle() {
    local off sleep lock="" args=(-w)
    read -r off sleep <<< "$(timers "$1")"
    [ "${setting[lock_screen]}" = yes ] && lock="$scripts/lock.sh; "

    if (( off > 0 )); then
        args+=(timeout $(( off * 60 )) "${lock}swaymsg 'output * power off'"
               resume "swaymsg 'output * power on'")
    fi
    if (( sleep > 0 )); then
        args+=(timeout $(( sleep * 60 )) "systemctl suspend")
    fi
    [ -n "$lock" ] && args+=(before-sleep "$scripts/lock.sh")
    args+=(after-resume "$scripts/on-resume.sh")

    swayidle "${args[@]}" &
    idle_pid=$!
}

stop_swayidle() {
    [ -n "$idle_pid" ] && kill "$idle_pid" 2>/dev/null && wait "$idle_pid" 2>/dev/null
    idle_pid=""
}

trap 'stop_swayidle; rm -f "$pidfile"; exit 0' TERM INT
trap ':' USR1     # wakes the loop below so new settings apply right away

current=""
while swaymsg -t get_version >/dev/null 2>&1; do    # stop when sway exits
    read_settings
    source=$(power_source)
    state="$source $(timers "$source") ${setting[lock_screen]}"
    if [ "$state" != "$current" ] || ! kill -0 "$idle_pid" 2>/dev/null; then
        stop_swayidle
        # A restart forgets that the idle timer turned the screen off, so
        # make sure it's on
        [ -n "$current" ] && swaymsg 'output * power on' >/dev/null
        start_swayidle "$source"
        current="$state"
    fi
    sleep 15 & wait $!
done

stop_swayidle
rm -f "$pidfile"
