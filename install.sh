#!/usr/bin/env bash
# Installs the sway setup on Fedora Asahi Remix.
#
#   ./install.sh                  install packages, then copy the configs
#   ./install.sh --no-packages    copy the configs only (packages already installed)
#   ./install.sh --greetd         also replace GDM with the lighter greetd login screen
#
# Flags can be combined. Existing configs are backed up to
# ~/.config/<name>.bak-<date> first; other files in those folders are left alone.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
stamp="$(date +%Y%m%d-%H%M%S)"
dirs=(sway waybar fuzzel mako swaylock)

install_packages=1
setup_greetd=0
for arg in "$@"; do
    case "$arg" in
        --no-packages) install_packages=0 ;;
        --greetd)      setup_greetd=1 ;;
        -h|--help)     sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)             echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

packages=(
    # compositor, idle, lock, wallpaper
    sway swayidle swaylock swaybg
    # bar, launcher, notifications, terminal
    waybar fuzzel mako foot
    # bar icons
    fontawesome-fonts-all
    # brightness, volume, media keys
    brightnessctl wireplumber playerctl
    # settings windows opened from the bar
    pavucontrol blueman NetworkManager-tui nm-connection-editor
    # screenshots and notifications from scripts
    grim slurp wl-clipboard libnotify xdg-user-dirs
    # password prompts for GUI apps, screen sharing
    lxpolkit xdg-desktop-portal-wlr
    # quick settings panel (sliders, battery, power mode)
    python3-gobject gtk3 upower
    # bigger text on the login screen and text consoles
    terminus-fonts-console
)
if (( setup_greetd )); then
    packages+=(greetd tuigreet)
fi

if (( install_packages || setup_greetd )); then
    echo "==> Installing packages (asks for your password)"
    if dnf --version 2>/dev/null | grep -qi dnf5; then
        skip=(--skip-unavailable)
    else
        skip=(--setopt=strict=0)
    fi
    if (( install_packages )); then
        sudo dnf install -y "${skip[@]}" "${packages[@]}"
    else
        sudo dnf install -y "${skip[@]}" greetd tuigreet terminus-fonts-console
    fi
fi

echo "==> Copying configs to $cfg"
for d in "${dirs[@]}"; do
    if [[ -e "$cfg/$d" ]]; then
        cp -a "$cfg/$d" "$cfg/$d.bak-$stamp"
        echo "    backed up $cfg/$d -> $d.bak-$stamp"
    fi
    mkdir -p "$cfg/$d"
    cp -r "$here/config/$d/." "$cfg/$d/"
done
chmod +x "$cfg/sway/scripts/"*.sh "$cfg/sway/scripts/"*.py "$cfg/waybar/scripts/"*.sh

# Refresh the font cache so the bar icons show up right away
fc-cache -f >/dev/null 2>&1 || true

echo "==> Checking the sway config"
if command -v sway >/dev/null &&
    WLR_BACKENDS=headless WLR_RENDERER=pixman sway -C -c "$cfg/sway/config" >/dev/null 2>&1; then
    echo "    sway config OK"
else
    echo "    sway reported a problem; run this to see it:"
    echo "    WLR_BACKENDS=headless WLR_RENDERER=pixman sway -C -c $cfg/sway/config"
fi

if (( setup_greetd )); then
    echo "==> Setting up the greetd login screen"
    conf=/etc/greetd/config.toml

    # Use the greeter account Fedora's greetd package created
    greeter=greetd
    if [[ -f "$conf" ]]; then
        found=$(sudo sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$conf" | head -1 || true)
        [[ -n "$found" ]] && greeter="$found"
        sudo cp -a "$conf" "$conf.bak-$stamp"
        echo "    backed up $conf -> config.toml.bak-$stamp"
    fi
    if ! id "$greeter" >/dev/null 2>&1; then
        echo "    The greeter account '$greeter' doesn't exist; is greetd installed?" >&2
        echo "    Leaving your current login screen alone." >&2
        exit 1
    fi

    sudo mkdir -p /etc/greetd
    sudo tee "$conf" >/dev/null <<EOF
# Written by the sway dotfiles install.sh. The old file is next to this one as .bak-<date>.
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --asterisks --cmd sway"
user = "$greeter"
EOF
    # tuigreet keeps the last user and session here (for --remember)
    sudo install -d -o "$greeter" -g "$greeter" -m 755 /var/cache/tuigreet

    # Bigger login screen text. tuigreet runs on the text console, whose
    # default font is tiny on a Retina screen, so use a Terminus console font
    # the same size as the 150% display scale. Change it later from the
    # quick-settings menu: Display scale -> Login screen text size.
    vconsole=/etc/vconsole.conf
    font=""
    for f in /usr/lib/kbd/consolefonts/ter-{v,u,i,1}24n.psf*; do
        if [[ -e "$f" ]]; then font=${f##*/}; font=${font%%.*}; break; fi
    done
    if grep -qs '^FONT="\{0,1\}ter-' "$vconsole"; then
        echo "    login screen text size already set in $vconsole"
    elif [[ -z "$font" ]]; then
        echo "    Terminus console fonts not found, so the login screen text stays small"
    else
        if [[ -f "$vconsole" ]]; then
            sudo cp -a "$vconsole" "$vconsole.bak-$stamp"
            echo "    backed up $vconsole -> vconsole.conf.bak-$stamp"
        fi
        if grep -qs '^FONT=' "$vconsole"; then
            sudo sed -i "s/^FONT=.*/FONT=\"$font\"/" "$vconsole"
        else
            echo "FONT=\"$font\"" | sudo tee -a "$vconsole" >/dev/null
        fi
        echo "    login screen text set to 150% ($font in $vconsole)"
    fi

    # Switch the display manager: turn off the current one (usually gdm), turn on greetd
    current=$(systemctl show -p Id --value display-manager.service 2>/dev/null || true)
    previous=gdm.service
    if [[ -n "$current" && "$current" != "greetd.service" && "$current" != "display-manager.service" ]]; then
        previous="$current"
        sudo systemctl disable "$current"
        echo "    disabled $current"
    fi
    sudo systemctl enable greetd.service
    echo "    greetd will show the login screen from the next reboot"
    cat <<EOF

    If the login screen doesn't appear after rebooting, press
    Ctrl+Option+F3 (hold fn too if needed), log in, and run:
        sudo systemctl disable greetd && sudo systemctl enable $previous
    then reboot to get the old login screen back.
EOF
fi

cat <<'EOF'

Done. Log out (sliders icon in the top right -> Log out) and log back into
sway so everything starts fresh.

Command and Control are swapped: Control is the sway key, Command copies
and pastes like Ctrl on other computers.

  Ctrl+?                   list of every shortcut (type to search)
  Ctrl+D or Ctrl+Space     app launcher
  Ctrl+Enter               terminal
  Ctrl+Shift+W             change wallpaper
  Ctrl+Shift+E             power menu
  Sliders icon (top right) quick settings

Undo: delete ~/.config/{sway,waybar,fuzzel,mako,swaylock} and rename the
.bak-<date> folders back.
EOF
