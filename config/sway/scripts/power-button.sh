#!/usr/bin/env bash
# What a short press of the power button does: put the Mac to sleep, like
# GNOME. (Holding the button down still forces the Mac off; that's the Mac
# itself, not this script.)
#
# The press that wakes the Mac can reach sway just after it resumes, so
# presses within a few seconds of waking are ignored. Otherwise pressing the
# button to wake it would send it straight back to sleep.

stamp="${XDG_RUNTIME_DIR:-/tmp}/sway-resumed-at"

if [ -f "$stamp" ] && (( $(date +%s) - $(cat "$stamp") < 5 )); then
    exit 0
fi

systemctl suspend
