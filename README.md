# Lean Sway for Apple Silicon Macs

Sway dotfiles for M-series Macs running [Fedora Asahi Remix](https://asahilinux.org/fedora/),
built to use as little memory as possible while still feeling like a
finished desktop: a top bar with quick settings, an app launcher,
notifications, a lock screen, screenshots and a wallpaper picker.
Command and Control are swapped, so Cmd+C and Cmd+V work like on macOS.

<!-- Add a screenshot: press Ctrl+Cmd+Shift+S, copy the file from
     ~/Pictures/Screenshots into this repo as screenshot.png, and
     uncomment the line below. -->
<!-- ![Desktop](screenshot.png) -->

## Why

On an 8 GB Mac every gigabyte matters. Measured on an M1 with 8 GB, idle
right after logging in:

<!-- TODO: fresh boot, log in, wait a minute, run `free -h`, and put the
     "used" number in the "This setup" row -->
| Desktop | RAM used at idle |
|---|---|
| GNOME (Fedora Asahi Remix default) | 2.73 GB |
| Stock sway | 1.07 GB |
| This setup | — |

Most of the savings come from not running things until you need them:

| Always running | Starts only when you use it |
|---|---|
| sway, swaybg (wallpaper) | fuzzel (launcher, menus, shortcut list) |
| waybar (top bar) | foot (terminal) |
| mako (notifications) | pavucontrol, blueman, nmtui (settings windows) |
| swayidle (auto-lock) | swaylock (lock screen) |
| lxpolkit (password prompts) | grim + slurp (screenshots) |

Choices made to keep it small:

- **Mako for notifications** instead of SwayNotificationCenter, which pulls in
  GTK4 and libadwaita.
- **Quick settings live in Waybar's own menu**, so there's no separate panel
  process sitting in memory.
- **No tray applets** (nm-applet, blueman-applet). The Wi-Fi, Bluetooth and
  sound icons open their settings windows when clicked, and those close
  when you're done.
- **Optional greetd + tuigreet login screen** instead of GDM, which runs a
  whole GNOME Shell just to show the login screen.

Two Asahi notes when comparing numbers: Asahi uses 16K memory pages, so the
same programs read a bit higher than on an x86 laptop, and Fedora enables
zram swap by default, so 8 GB stretches further than it looks.

## Requirements

- A Mac that [Fedora Asahi Remix](https://asahilinux.org/fedora/) supports
- Fedora Asahi Remix installed (any desktop; GNOME is fine, it stays installed
  and you can still pick it at login)

The installer uses `dnf`. On another distro, install the packages listed at
the top of `install.sh` yourself and copy the `config/` folders into
`~/.config/`.

## Install

```
git clone https://github.com/YOUR-NAME/YOUR-REPO.git
cd YOUR-REPO
./install.sh
```

Then log out, pick **Sway** at the login screen, and log in.

| Command | What it does |
|---|---|
| `./install.sh` | Installs the packages, then copies the configs |
| `./install.sh --no-packages` | Copies the configs only. Use this to update after the packages are already installed |
| `./install.sh --greetd` | Also replaces GDM with the greetd + tuigreet login screen (takes effect after a reboot) |

Flags can be combined, e.g. `./install.sh --no-packages --greetd`.

Your existing configs are backed up to `~/.config/<name>.bak-<date>` before
anything is copied, and other files in those folders are left alone.
`--greetd` also backs up `/etc/greetd/config.toml`, and prints how to switch
back to GDM if the new login screen doesn't come up.

## Keyboard

**Command and Control are swapped.** The **Control** key is sway's Mod key
for window shortcuts, and **Command** acts like Ctrl does on other
computers: Cmd+C copies, Cmd+V pastes, Cmd+T opens a tab, Cmd+Q quits.
Key names below are the printed keys on the Mac keyboard.

Press **Ctrl+?** (Ctrl+Shift+/) at any time for a searchable list of every
shortcut.

| Keys | Action |
|---|---|
| Ctrl+? | Shortcut list (type to search, Esc to close) |
| Ctrl+D or Ctrl+Space | App launcher |
| Ctrl+Enter | Terminal |
| Ctrl+Shift+Q | Close window |
| Ctrl+Shift+E | Power menu |
| Ctrl+Cmd+Q | Lock (same as macOS) |
| Ctrl+Shift+C | Reload sway and the bar |
| Cmd+C / X / V / Z | Copy / cut / paste / undo in apps |
| Cmd+Shift+C / V | Copy / paste in the terminal (Cmd+C stops a command there) |
| Ctrl+arrows or H/J/K/L | Move focus (add Shift to move the window) |
| Ctrl+1…0 / Ctrl+Shift+1…0 | Go to / send window to workspace |
| Ctrl+Tab | Previous workspace |
| Ctrl+F | Fullscreen |
| Ctrl+Shift+Space | Float / tile window |
| Ctrl+drag | Move a floating window (right-drag resizes) |
| Ctrl+R | Resize mode (arrows, Esc to leave) |
| Ctrl+B / Ctrl+V | Next window opens beside / below |
| Ctrl+W / Ctrl+S / Ctrl+E | Tabbed / stacked / split layout |
| Ctrl+Shift+S | Screenshot an area (Ctrl+Cmd+Shift+S: whole screen) |
| Ctrl+Shift+W | Change wallpaper |
| Ctrl+N | Do Not Disturb on/off |

The top-row brightness, keyboard light, media and volume keys work as on
macOS. Screenshots are saved to `~/Pictures/Screenshots` and copied to the
clipboard.

Prefer the normal layout? Delete the `xkb_options` line in
`~/.config/sway/config` and reload. The Mod key then moves to Command.

## The bar

| Where | What | Click | Right-click / scroll |
|---|---|---|---|
| Far left | Apps grid | Open the launcher | |
| Left | Workspaces | Switch | |
| Middle | Clock | Hover for a calendar | |
| Middle | Muted bell | Only shows during Do Not Disturb; click to end it | |
| Right | Wi-Fi | Pick a network | Right-click: connection settings |
| Right | Bluetooth | Devices | Right-click: turn on/off |
| Right | Volume | Sound settings | Scroll: volume. Right-click: mute |
| Right | Sun | | Scroll: brightness |
| Right | Battery | Hover for time left | |
| Far right | Sliders | Quick settings: Wi-Fi, Bluetooth, sound, on/off toggles, Do Not Disturb, screenshot, wallpaper, shortcuts, lock, suspend, log out, reboot, shut down | |

The brightness and battery icons hide themselves on Macs without them
(Mac mini, Mac Studio).

## Wallpaper

Press **Ctrl+Shift+W** (or use the sliders menu) to pick an image from
`~/Pictures` or Fedora's built-in wallpapers. Keep your own in
`~/Pictures/Wallpapers` so they're easy to find. From a terminal:

```
~/.config/sway/scripts/wallpaper.sh ~/Downloads/photo.jpg       # fill the screen
~/.config/sway/scripts/wallpaper.sh ~/Downloads/photo.jpg fit   # or center, tile, stretch
~/.config/sway/scripts/wallpaper.sh none                        # plain dark background
```

The image is copied into `~/.config/sway/`, so it stays after reboots even if
the original is moved or deleted. JPG and PNG work.

## Customizing

| To change | Edit |
|---|---|
| Display scale (default 1.5) | `set $scale` near the top of `~/.config/sway/config` |
| Bar colors | The `@define-color` lines at the top of `~/.config/waybar/style.css` |
| Bar contents | `~/.config/waybar/config.jsonc` |
| Quick-settings menu items | `~/.config/waybar/control_menu.xml` plus `menu-actions` in `config.jsonc` |
| Shortcut list | `~/.config/sway/keybinds.txt` (update it when you change a binding) |
| Lock / screen-off timers | The `swayidle` lines in `~/.config/sway/config` |
| Touchpad | The `input type:touchpad` block in `~/.config/sway/config` |
| Launcher look | `~/.config/fuzzel/fuzzel.ini` |
| Notification look | `~/.config/mako/config` |
| Lock screen colors | `~/.config/swaylock/config` |

The same palette is used everywhere: background `#16161e`, accent `#7aa2f7`.
Search and replace those two across the files to retheme. Press Ctrl+Shift+C
after editing.

## Repo layout

```
install.sh                 installer (packages, configs, optional greetd)
config/
  sway/config              compositor: keys, touchpad, idle, autostart, look
  sway/keybinds.txt        the Ctrl+? shortcut list
  sway/scripts/            power menu, screenshots, toggles, wallpaper, shortcut list
  waybar/                  bar layout, style, quick-settings menu
  fuzzel/fuzzel.ini        launcher
  mako/config              notifications
  swaylock/config          lock screen
```

## Keeping memory low

- Check what's using memory: `ps -eo rss,comm --sort=-rss | head -20`
  (RSS is in KB).
- If GNOME background services show up in a sway session (`gnome-software`,
  `evolution-*`, `localsearch`), disable or remove them.
- Measure the same way every time: fresh boot, log in, wait a minute, then
  `free -h`. Different tools (htop, btop, GNOME System Monitor) count memory
  differently.
- Your browser will use more memory than everything here combined. Fewer
  open tabs helps more than any desktop tweak.

## Troubleshooting

**Bar icons show as boxes.** Check the icon font is installed with
`fc-list | grep -i awesome`. If nothing shows, run
`sudo dnf install fontawesome-fonts-all && fc-cache -f`, then Ctrl+Shift+C.

**Bar didn't appear.** Run `waybar` in a terminal; it prints the line it
doesn't like.

**An app says there's no authentication agent.** Check lxpolkit is
running: `pgrep -a lxpolkit`.

**Login screen didn't come up after `--greetd`.** Press Ctrl+Option+F3
(hold fn too if needed), log in, then run
`sudo systemctl disable greetd && sudo systemctl enable gdm` and reboot.

## Uninstall

Delete `~/.config/{sway,waybar,fuzzel,mako,swaylock}` and rename the
`.bak-<date>` folders back. GNOME is untouched, so you can pick it at the
login screen any time.

## Want a GNOME-style panel with sliders?

SwayNotificationCenter (swaync) adds a pull-out panel with volume and
brightness sliders, toggle buttons, media controls and notification history.
It replaces mako, but uses noticeably more memory, and on Fedora it comes
from a COPR repo (`erikreider/SwayNotificationCenter`). It's left out on
purpose.

## Credits

Built on [sway](https://swaywm.org), [Waybar](https://github.com/Alexays/Waybar),
[fuzzel](https://codeberg.org/dnkl/fuzzel), [mako](https://github.com/emersion/mako),
[swaylock](https://github.com/swaywm/swaylock) and
[Font Awesome](https://fontawesome.com) icons, on top of the
[Asahi Linux](https://asahilinux.org) project. Colors adapted from the
Tokyo Night palette.
