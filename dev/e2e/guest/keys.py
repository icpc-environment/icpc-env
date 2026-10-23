#!/usr/bin/python3 -I
# Press key combos like a keyboard would: keys.py ctrl+shift+F10 Return ...
# xdotool looks keysyms up in its own way and can pick a keycode that carries
# a modifier; e.g. its F9 lands on xfwm's Alt+F9 "hide window" binding. This
# uses each keysym's primary keycode instead.
import sys, time
from Xlib import X, XK, display
from Xlib.ext import xtest

ALIASES = {"ctrl": "Control_L", "control": "Control_L", "shift": "Shift_L", "alt": "Alt_L",
           "super": "Super_L", "meta": "Meta_L", "enter": "Return", "esc": "Escape",
           "grave": "grave", "plus": "plus", "minus": "minus"}

d = display.Display()


def keycode(name):
    sym = XK.string_to_keysym(ALIASES.get(name.lower(), name))
    if sym == 0 and len(name) == 1:
        sym = ord(name)
    codes = d.keysym_to_keycodes(sym)
    # Lowest shift level first, then lowest keycode
    best = min(codes, key=lambda c: (c[1], c[0]), default=None)
    if best is None:
        sys.exit(f"unknown key {name}")
    return best[0]


for combo in sys.argv[1:]:
    codes = [keycode(k) for k in combo.split("+")]
    for c in codes:
        xtest.fake_input(d, X.KeyPress, c)
        d.sync()
        time.sleep(0.01)
    for c in reversed(codes):
        xtest.fake_input(d, X.KeyRelease, c)
        d.sync()
        time.sleep(0.01)
    time.sleep(0.05)
