#!/usr/bin/env python3
"""A GNOME-style quick settings panel that drops down from the top bar:
volume and brightness sliders, battery status with time left or time to full,
and power mode. Opened by clicking the volume, brightness or battery icon.
Click the icon again, press Esc, or click another window to close it.

It only runs while it's open, so it costs no memory the rest of the time.
"""

import json
import os
import signal
import subprocess
import sys

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PIDFILE = os.path.join(RUNTIME, "sway-quick-panel.pid")
SCRIPTS = os.path.expanduser("~/.config/sway/scripts")
APP_ID = "sway-quick-panel"
SINK = "@DEFAULT_AUDIO_SINK@"
KBD = "*kbd_backlight*"


def running_panel():
    """PID of an open panel, if there is one."""
    try:
        pid = int(open(PIDFILE).read())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"quick-panel" in f.read():
                return pid
    except (OSError, ValueError):
        pass
    return None


# Clicking the icon while the panel is open closes it
pid = running_panel()
if pid:
    os.kill(pid, signal.SIGTERM)
    sys.exit(0)
with open(PIDFILE, "w") as f:
    f.write(str(os.getpid()))

import gi  # noqa: E402

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import GLib  # noqa: E402

GLib.set_prgname(APP_ID)  # becomes the window's app_id, which sway's rules match
from gi.repository import Gdk, Gio, Gtk  # noqa: E402


def run(*cmd):
    """Start a command without waiting for it."""
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def output(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def get_volume():
    """(percent, muted) or (None, False) if there's no audio output."""
    parts = output("wpctl", "get-volume", SINK).split()  # "Volume: 0.45 [MUTED]"
    try:
        return round(float(parts[1]) * 100), "[MUTED]" in parts
    except (IndexError, ValueError):
        return None, False


def get_brightness(device=None):
    """Percent, or None if there's no such light (e.g. a Mac mini)."""
    cmd = ["brightnessctl", "-m"] + (["-d", device] if device else [])
    fields = output(*cmd).strip().split(",")  # "name,class,current,45%,max"
    if len(fields) < 5 or (device is None and fields[1] != "backlight"):
        return None
    try:
        return int(fields[3].rstrip("%"))
    except ValueError:
        return None


# ---- battery and power mode (read from UPower / power-profiles over D-Bus) ----

UPOWER_STATES = {1: "charging", 2: "discharging", 3: "discharging", 4: "full",
                 5: "not charging", 6: "discharging"}
SYSFS_STATES = {"Charging": "charging", "Discharging": "discharging", "Full": "full",
                "Not charging": "not charging"}
PROFILE_NAMES = {"power-saver": "Power Saver", "balanced": "Balanced",
                 "performance": "Performance"}
PROFILE_SERVICES = [  # newer name first, then the original power-profiles-daemon name
    ("org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles"),
    ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles"),
]


def system_bus():
    try:
        return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    except GLib.Error:
        return None


def get_properties(bus, service, path, interface):
    try:
        reply = bus.call_sync(service, path, "org.freedesktop.DBus.Properties", "GetAll",
                              GLib.Variant("(s)", (interface,)), GLib.VariantType("(a{sv})"),
                              Gio.DBusCallFlags.NONE, 1500, None)
        return reply.unpack()[0]
    except GLib.Error:
        return None


def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def sysfs_battery():
    """Battery info straight from the kernel, if UPower isn't available."""
    base = "/sys/class/power_supply"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return None
    for name in names:
        d = os.path.join(base, name)
        if read_file(f"{d}/type") != "Battery":
            continue
        num = lambda f: int(read_file(f"{d}/{f}") or 0)  # noqa: E731
        state = SYSFS_STATES.get(read_file(f"{d}/status"), "discharging")
        to_empty, to_full = num("time_to_empty_now"), num("time_to_full_now")
        rate = num("power_now") or num("current_now")
        now, full = (num("energy_now"), num("energy_full")) if num("power_now") \
            else (num("charge_now"), num("charge_full"))
        if rate and not to_empty and state == "discharging":
            to_empty = now * 3600 // rate
        if rate and not to_full and state == "charging":
            to_full = max(full - now, 0) * 3600 // rate
        return {"percent": num("capacity"), "state": state,
                "to_empty": to_empty, "to_full": to_full}
    return None


def battery_info(bus):
    """{"percent", "state", "to_empty", "to_full"} or None without a battery."""
    if bus:
        p = get_properties(bus, "org.freedesktop.UPower",
                           "/org/freedesktop/UPower/devices/DisplayDevice",
                           "org.freedesktop.UPower.Device")
        if p and p.get("IsPresent") and p.get("Type") == 2:  # 2 = battery
            return {"percent": round(p.get("Percentage", 0)),
                    "state": UPOWER_STATES.get(p.get("State"), "discharging"),
                    "to_empty": int(p.get("TimeToEmpty", 0)),
                    "to_full": int(p.get("TimeToFull", 0))}
    return sysfs_battery()


def duration(seconds):
    minutes = max(1, round(seconds / 60))
    hours, minutes = divmod(minutes, 60)
    if hours and minutes:
        return f"{hours} h {minutes} min"
    return f"{hours} h" if hours else f"{minutes} min"


def battery_text(info):
    state = info["state"]
    if state == "charging":
        return f"Charging, full in {duration(info['to_full'])}" if info["to_full"] \
            else "Charging"
    if state == "full":
        return "Fully charged"
    if state == "not charging":
        return "Plugged in, not charging"
    return f"About {duration(info['to_empty'])} left" if info["to_empty"] \
        else "On battery, estimating time left…"


def battery_icon(info):
    if info["state"] == "charging":
        return ICONS["bolt"]
    if info["state"] in ("full", "not charging"):
        return ICONS["plug"]
    level = info["percent"]
    return ICONS["bat0" if level < 10 else "bat1" if level < 35 else "bat2" if level < 60
                 else "bat3" if level < 85 else "bat4"]


def power_profiles(bus):
    """(service, path, active profile, [profiles]) or None if power modes aren't available."""
    if not bus:
        return None
    for service, path in PROFILE_SERVICES:
        p = get_properties(bus, service, path, service)
        if p and p.get("Profiles"):
            names = [prof.get("Profile") for prof in p["Profiles"]]
            order = [n for n in PROFILE_NAMES if n in names]
            return service, path, p.get("ActiveProfile"), order
    return None


ICONS = {"high": "", "low": "", "off": "", "muted": "",
         "sun": "",
         "bat0": "\uf244", "bat1": "\uf243", "bat2": "\uf242", "bat3": "\uf241",
         "bat4": "\uf240", "bolt": "\uf0e7", "plug": "\uf1e6"}

CSS = b"""
window { background-color: transparent; }
.panel {
    background-color: #16161e;
    border: 1px solid #2a2c3a;
    border-radius: 16px;
    padding: 16px 18px;
}
label { color: #e6e6ef; }
.icon {
    font-family: "Font Awesome 6 Free";
    font-weight: 900;
    font-size: 14px;
}
.icon-button, .icon-plain {
    min-width: 34px;
    min-height: 34px;
    padding: 0;
    border-radius: 17px;
    border: none;
    box-shadow: none;
    background-image: none;
    background-color: #2a2c3a;
    color: #e6e6ef;
}
.icon-button:hover { background-color: #34374a; }
.icon-button.muted { background-color: #f7768e; color: #16161e; }
.icon-plain { background-color: transparent; }
scale { padding: 0 6px; }
scale trough {
    min-height: 6px;
    border-radius: 3px;
    border: none;
    background-color: #2a2c3a;
}
scale highlight {
    border-radius: 3px;
    border: none;
    background-image: none;
    background-color: #7aa2f7;
}
scale slider {
    min-width: 18px;
    min-height: 18px;
    margin: -7px;
    border-radius: 9px;
    border: none;
    box-shadow: none;
    background-image: none;
    background-color: #e6e6ef;
}
.value { color: #8a8ca0; min-width: 40px; }
.action {
    padding: 8px 14px;
    border-radius: 18px;
    border: none;
    box-shadow: none;
    background-image: none;
    background-color: #1f2029;
    color: #e6e6ef;
}
.action:hover { background-color: #2a2c3a; }
.action.on { background-color: #7aa2f7; color: #16161e; }
separator { background-color: #2a2c3a; min-height: 1px; }
.battery { font-weight: bold; }
.dim { color: #8a8ca0; }
.mode {
    padding: 7px 10px;
    border-radius: 0;
    border: none;
    box-shadow: none;
    background-image: none;
    background-color: #1f2029;
    color: #e6e6ef;
}
.mode:hover { background-color: #2a2c3a; }
.mode.first { border-radius: 16px 0 0 16px; }
.mode.last { border-radius: 0 16px 16px 0; }
.mode.on { background-color: #7aa2f7; color: #16161e; }
"""


class Panel(Gtk.Window):
    def __init__(self):
        super().__init__(title="Quick settings")
        self.set_decorated(False)
        self.set_resizable(False)
        visual = self.get_screen().get_rgba_visual()
        if visual:  # transparent corners around the rounded panel
            self.set_visual(visual)
            self.set_app_paintable(True)

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.pending = {}
        self.muted = False
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.get_style_context().add_class("panel")
        self.add(box)

        volume, self.muted = get_volume()
        if volume is not None:
            self.mute_button = Gtk.Button()
            self.mute_label = Gtk.Label()
            self.mute_label.get_style_context().add_class("icon")
            self.mute_button.add(self.mute_label)
            self.mute_button.get_style_context().add_class("icon-button")
            self.mute_button.set_tooltip_text("Mute / unmute")
            self.mute_button.connect("clicked", self.toggle_mute)
            self.volume_scale, self.volume_value = self.add_slider(
                box, self.mute_button, volume, 0, "volume")
            self.show_volume_icon(volume)

        brightness = get_brightness()
        if brightness is not None:
            sun = Gtk.Label(label=ICONS["sun"])
            sun.get_style_context().add_class("icon")
            holder = Gtk.Box()
            holder.get_style_context().add_class("icon-plain")
            holder.pack_start(sun, True, True, 0)
            self.add_slider(box, holder, brightness, 1, "brightness")

        # Battery and power mode
        self.bus = system_bus()
        self.battery = battery_info(self.bus)
        self.profiles = power_profiles(self.bus)
        if self.battery or self.profiles:
            box.pack_start(Gtk.Separator(), False, False, 0)
        if self.battery:
            row = Gtk.Box(spacing=10)
            self.battery_icon = Gtk.Label()
            self.battery_icon.get_style_context().add_class("icon")
            icon_box = Gtk.Box()
            icon_box.get_style_context().add_class("icon-plain")
            icon_box.pack_start(self.battery_icon, True, True, 0)
            self.battery_percent = Gtk.Label(xalign=0)
            self.battery_percent.get_style_context().add_class("battery")
            self.battery_status = Gtk.Label(xalign=0)
            self.battery_status.get_style_context().add_class("dim")
            row.pack_start(icon_box, False, False, 0)
            row.pack_start(self.battery_percent, False, False, 0)
            row.pack_start(self.battery_status, False, False, 0)
            box.pack_start(row, False, False, 0)
            self.show_battery()
            GLib.timeout_add_seconds(10, self.refresh_battery)
        if self.profiles:
            service, path, active, names = self.profiles
            row = Gtk.Box(spacing=0, homogeneous=True)
            self.mode_buttons = {}
            for i, name in enumerate(names):
                button = Gtk.Button(label=PROFILE_NAMES[name])
                ctx = button.get_style_context()
                ctx.add_class("mode")
                if i == 0:
                    ctx.add_class("first")
                if i == len(names) - 1:
                    ctx.add_class("last")
                button.connect("clicked", self.choose_profile, name)
                self.mode_buttons[name] = button
                row.pack_start(button, True, True, 0)
            caption = Gtk.Label(label="Power mode", xalign=0)
            caption.get_style_context().add_class("dim")
            box.pack_start(caption, False, False, 0)
            box.pack_start(row, False, False, 0)
            self.show_profile(active)

        # Buttons under the sliders
        actions = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                              max_children_per_line=2, column_spacing=8, row_spacing=8,
                              homogeneous=True)
        if volume is not None:
            self.add_action(actions, "Output device", f"{SCRIPTS}/audio.sh", "output")
            self.add_action(actions, "Microphone", f"{SCRIPTS}/audio.sh", "input")
        kbd = get_brightness(KBD)
        if kbd is not None:
            self.kbd_button = self.add_action(actions, "Keyboard light", None)
            self.kbd_button.connect("clicked", self.toggle_keyboard)
            self.show_keyboard(kbd > 0)
        if volume is not None:
            self.add_action(actions, "Sound settings", "pavucontrol")
        if actions.get_children():
            box.pack_start(Gtk.Separator(), False, False, 0)
            box.pack_start(actions, False, False, 0)

        if volume is None and brightness is None and not self.battery and not self.profiles:
            box.pack_start(Gtk.Label(label="No controls found"), False, False, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("map-event", lambda *_: GLib.timeout_add(20, self.place))
        self.connect("destroy", Gtk.main_quit)

    # ---- building blocks ----------------------------------------------------

    def add_slider(self, box, icon, value, lowest, kind):
        row = Gtk.Box(spacing=10)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lowest, 100, 1)
        scale.set_draw_value(False)
        scale.set_size_request(230, -1)
        scale.set_value(value)
        label = Gtk.Label(label=f"{value}%", xalign=1)
        label.get_style_context().add_class("value")
        scale.connect("value-changed", self.on_slide, kind, label)
        row.pack_start(icon, False, False, 0)
        row.pack_start(scale, True, True, 0)
        row.pack_start(label, False, False, 0)
        box.pack_start(row, False, False, 0)
        return scale, label

    def add_action(self, flow, text, command, *args):
        button = Gtk.Button(label=text)
        button.get_style_context().add_class("action")
        if command:
            button.connect("clicked", lambda *_: (run(command, *args), self.close()))
        flow.add(button)
        return button

    # ---- volume -------------------------------------------------------------

    def show_volume_icon(self, value):
        ctx = self.mute_button.get_style_context()
        if self.muted:
            self.mute_label.set_text(ICONS["muted"])
            ctx.add_class("muted")
        else:
            ctx.remove_class("muted")
            icon = "off" if value == 0 else "low" if value < 50 else "high"
            self.mute_label.set_text(ICONS[icon])

    def toggle_mute(self, *_):
        self.muted = not self.muted
        run("wpctl", "set-mute", SINK, "1" if self.muted else "0")
        self.show_volume_icon(int(self.volume_scale.get_value()))

    # ---- sliders ------------------------------------------------------------

    def on_slide(self, scale, kind, label):
        value = int(scale.get_value())
        label.set_text(f"{value}%")
        if kind == "volume":
            if self.muted and value > 0:  # moving the slider unmutes, like GNOME
                self.muted = False
                self.pending["unmute"] = True
            self.show_volume_icon(value)
        # Apply at most every 40 ms while dragging
        if not self.pending.get(kind + "_queued"):
            self.pending[kind + "_queued"] = True
            GLib.timeout_add(40, self.apply, kind, scale)

    def apply(self, kind, scale):
        self.pending.pop(kind + "_queued", None)
        value = int(scale.get_value())
        if kind == "volume":
            run("wpctl", "set-volume", "-l", "1.0", SINK, f"{value / 100:.2f}")
            if self.pending.pop("unmute", False):
                run("wpctl", "set-mute", SINK, "0")
        else:
            run("brightnessctl", "-q", "set", f"{max(1, value)}%")
        return False

    # ---- battery and power mode ---------------------------------------------

    def show_battery(self):
        self.battery_icon.set_text(battery_icon(self.battery))
        self.battery_percent.set_text(f"{self.battery['percent']}%")
        self.battery_status.set_text(battery_text(self.battery))

    def refresh_battery(self):
        info = battery_info(self.bus)
        if info:
            self.battery = info
            self.show_battery()
        return True  # keep refreshing while the panel is open

    def show_profile(self, active):
        for name, button in self.mode_buttons.items():
            ctx = button.get_style_context()
            (ctx.add_class if name == active else ctx.remove_class)("on")

    def choose_profile(self, _button, name):
        service, path, _active, _names = self.profiles
        try:
            self.bus.call_sync(service, path, "org.freedesktop.DBus.Properties", "Set",
                               GLib.Variant("(ssv)", (service, "ActiveProfile",
                                                      GLib.Variant("s", name))),
                               None, Gio.DBusCallFlags.NONE, 3000, None)
            self.show_profile(name)
        except GLib.Error as e:
            run("notify-send", "-u", "critical", "Couldn't change the power mode", e.message)

    # ---- keyboard light -----------------------------------------------------

    def show_keyboard(self, on):
        ctx = self.kbd_button.get_style_context()
        (ctx.add_class if on else ctx.remove_class)("on")

    def toggle_keyboard(self, *_):
        on = "on" not in self.kbd_button.get_style_context().list_classes()
        run("brightnessctl", "-q", "-d", KBD, "set", "50%" if on else "0")
        self.show_keyboard(on)

    # ---- window behaviour ---------------------------------------------------

    def on_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
        return False

    def place(self):
        """Put the panel in the top-right corner, under the bar, then show it."""
        width, height = self.get_allocated_width(), self.get_allocated_height()
        try:
            outputs = json.loads(output("swaymsg", "-t", "get_outputs", "-r") or "[]")
            screen = next((o for o in outputs if o.get("focused")), outputs[0])["rect"]
            x = screen["x"] + screen["width"] - width - 8
            y = screen["y"] + 44
            run("swaymsg", f'[app_id="{APP_ID}"] move absolute position {x} {y}, opacity 1')
        except (ValueError, IndexError, KeyError, StopIteration):
            run("swaymsg", f'[app_id="{APP_ID}"] opacity 1')
        # Close when you click another window (after the panel has settled)
        GLib.timeout_add(300, lambda: self.connect("focus-out-event",
                                                   self.on_focus_out) and False)
        return False

    def on_focus_out(self, *_):
        # Keyboard changes (e.g. a new keyboard being connected) briefly take
        # focus away and give it straight back; only close if it stays away.
        GLib.timeout_add(250, lambda: (self.is_active() or self.close()) and False)
        return False


def main():
    # Clicking the icon again sends SIGTERM: close cleanly
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
    panel = Panel()
    panel.show_all()
    try:
        Gtk.main()
    finally:
        try:
            if running_panel() == os.getpid():
                os.remove(PIDFILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
