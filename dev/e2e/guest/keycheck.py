#!/usr/bin/python3 -I
# Which key combos reach an application: keycheck.py ctrl+F5 alt+F7 ...
# Opens a window, focuses it, presses each combo with XTEST and reports, one
# line per combo, "ok COMBO" if the window got the key or "grabbed COMBO" if
# something (the window manager) took it first. Escape follows each combo to
# end any move/resize mode a window manager binding started.
import sys, time
from Xlib import X, XK, display, error
from Xlib.ext import xtest

ALIASES = {"ctrl": "Control_L", "shift": "Shift_L", "alt": "Alt_L", "super": "Super_L"}
d = display.Display()
d.set_error_handler(lambda *a: None)
s = d.screen()
w = s.root.create_window(200, 200, 400, 200, 0, s.root_depth, event_mask=X.KeyPressMask)
w.set_wm_name("e2e keycheck")
w.map()
d.sync()
time.sleep(1)


def code(name):
    sym = XK.string_to_keysym(ALIASES.get(name.lower(), name))
    return min(d.keysym_to_keycodes(sym), key=lambda c: (c[1], c[0]))[0]


def press(codes):
    for c in codes:
        xtest.fake_input(d, X.KeyPress, c)
    for c in reversed(codes):
        xtest.fake_input(d, X.KeyRelease, c)
    d.sync()


def drain():
    got = []
    end = time.time() + 0.6
    while time.time() < end:
        while d.pending_events():
            e = d.next_event()
            if e.type == X.KeyPress:
                got.append(e.detail)
        time.sleep(0.02)
    return got


def refocus():
    # Bindings like alt+F9 (hide) or alt+F10 (maximize) act on this window
    w.map()
    w.configure(x=200, y=200, width=400, height=200, stack_mode=X.Above)
    d.sync()
    time.sleep(0.4)
    try:
        w.set_input_focus(X.RevertToParent, X.CurrentTime)
        d.sync()
    except Exception:
        pass
    time.sleep(0.2)


for combo in sys.argv[1:]:
    refocus()
    drain()
    codes = [code(k) for k in combo.split("+")]
    press(codes)
    got = drain()
    print(("ok" if codes[-1] in got else "grabbed"), combo, flush=True)
    press([code("Escape")])
    drain()
