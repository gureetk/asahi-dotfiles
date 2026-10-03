#!/usr/bin/env bash
# Bluetooth device picker. Lists paired devices; picking one connects it,
# or disconnects it if it's already connected. New devices are paired in
# Blueman (last entry). Opened from the Bluetooth icon's menu in the bar.

notify() { notify-send -t 3000 -a bluetooth "$@"; }

if ! bluetoothctl show | grep -q "Powered: yes"; then
    rfkill unblock bluetooth 2>/dev/null
    bluetoothctl power on >/dev/null
    notify "Bluetooth on"
    sleep 1
fi

# Paired devices as "MAC name". Newer BlueZ: "devices Paired"; older: "paired-devices".
paired=$(bluetoothctl devices Paired 2>/dev/null | grep '^Device ')
[ -n "$paired" ] || paired=$(bluetoothctl paired-devices 2>/dev/null | grep '^Device ')

macs=() names=() connected=() labels=()
while read -r _ mac name; do
    [ -n "$mac" ] || continue
    is_on=0
    bluetoothctl info "$mac" | grep -q "Connected: yes" && is_on=1
    macs+=("$mac"); names+=("$name"); connected+=("$is_on")
    if (( is_on )); then labels+=("●  $name   (connected)"); else labels+=("    $name"); fi
done <<< "$paired"
labels+=("+  Pair a new device…")

idx=$(printf '%s\n' "${labels[@]}" |
      fuzzel --dmenu --index --no-sort --prompt "Bluetooth ❯ " --width 40 \
                   --lines "$(( ${#labels[@]} < 12 ? ${#labels[@]} : 12 ))") || exit 0
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

if (( idx >= ${#macs[@]} )); then
    blueman-manager &
    exit 0
fi

mac="${macs[$idx]}" name="${names[$idx]}"
if (( connected[idx] )); then
    bluetoothctl disconnect "$mac" >/dev/null
    notify "Disconnected $name"
else
    notify "Connecting to $name…"
    if bluetoothctl connect "$mac" | grep -q "Connection successful"; then
        notify "Connected to $name"
    else
        notify -u critical "Couldn't connect to $name" "Is it turned on and nearby?"
    fi
fi
