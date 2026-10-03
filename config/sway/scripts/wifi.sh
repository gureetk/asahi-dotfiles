#!/usr/bin/env bash
# Wi-Fi network picker. Lists nearby networks (connected one first, then
# strongest), connects to the one you pick, and asks for a password only for
# new secured networks. Opened from the Wi-Fi icon's menu in the bar.

notify() { notify-send -t 3000 -a wifi "$@"; }

if [ "$(nmcli radio wifi)" != "enabled" ]; then
    nmcli radio wifi on
    notify "Wi-Fi on" "Looking for networks…"
    sleep 4
fi

# Nearby networks as "<in use 1/0>\t<signal>\t<security or -->\t<ssid>",
# one line per network name, keeping the connected or strongest access point.
list_networks() {
    nmcli -t -e no -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto 2>/dev/null |
    awk -F: '{
        inuse = ($1 == "*") ? 1 : 0
        signal = $2 + 0
        sec = ($3 == "") ? "--" : $3
        ssid = $0; sub(/^[^:]*:[^:]*:[^:]*:/, "", ssid)    # SSID is last and may contain ":"
        if (ssid == "" || keep[ssid]) next                # skip hidden networks
        if (inuse) keep[ssid] = 1
        if (inuse || !(ssid in best) || signal > best[ssid]) {
            best[ssid] = signal
            row[ssid] = inuse "\t" signal "\t" sec "\t" ssid
        }
    }
    END { for (s in row) print row[s] }' |
    sort -t$'\t' -k1,1nr -k2,2nr
}

# Name of the saved profile for an SSID, if there is one
saved_profile() {
    nmcli -t -e no -f TYPE,NAME connection show | while IFS= read -r line; do
        [[ "$line" == 802-11-wireless:* ]] || continue
        name="${line#802-11-wireless:}"
        if [ "$(nmcli -g 802-11-wireless.ssid connection show "$name")" = "$1" ]; then
            printf '%s\n' "$name"
            break
        fi
    done
}

inuse=() ssids=() secs=() labels=()
while IFS=$'\t' read -r used signal security ssid; do
    inuse+=("$used"); ssids+=("$ssid"); secs+=("$security")
    mark="    "; [ "$used" = 1 ] && mark="●  "
    lock="";     [ "$security" != "--" ] && lock="  🔒"
    labels+=("$mark$ssid   $signal%$lock")
done < <(list_networks)

if (( ${#ssids[@]} == 0 )); then
    notify "No Wi-Fi networks found" "Try again in a moment."
    exit 0
fi

idx=$(printf '%s\n' "${labels[@]}" |
      fuzzel --dmenu --index --no-sort --prompt "Wi-Fi ❯ " --width 40 \
                   --lines "$(( ${#labels[@]} < 12 ? ${#labels[@]} : 12 ))") || exit 0
[[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#ssids[@]} )) || exit 0
ssid="${ssids[$idx]}" security="${secs[$idx]}"

if [ "${inuse[$idx]}" = 1 ]; then
    notify "Already connected to $ssid"
    exit 0
fi

ask_password() {
    fuzzel --dmenu --password --prompt-only "Password for $ssid ❯ "
}

if [[ "$security" == *802.1X* ]]; then
    notify "$ssid needs a username and more settings" "Opening network settings…"
    nm-connection-editor &
    exit 0
fi

profile=$(saved_profile "$ssid")

if [ -n "$profile" ]; then
    result=$(nmcli connection up id "$profile" 2>&1); status=$?
    # The saved password may be out of date: ask for it again and retry
    if (( status != 0 )) && [ "$security" != "--" ]; then
        password=$(ask_password) || exit 0
        [ -n "$password" ] || exit 0
        nmcli connection modify id "$profile" wifi-sec.psk "$password"
        result=$(nmcli connection up id "$profile" 2>&1); status=$?
    fi
else
    if [ "$security" != "--" ]; then
        password=$(ask_password) || exit 0
        [ -n "$password" ] || exit 0
        result=$(nmcli device wifi connect "$ssid" password "$password" 2>&1); status=$?
    else
        result=$(nmcli device wifi connect "$ssid" 2>&1); status=$?
    fi
    # Don't keep a profile with a wrong password around
    if (( status != 0 )); then
        nmcli connection delete id "$ssid" >/dev/null 2>&1
    fi
fi

if (( status == 0 )); then
    notify "Connected to $ssid"
else
    notify -u critical "Couldn't connect to $ssid" "$result"
fi
