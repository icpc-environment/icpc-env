#!/usr/bin/env python3
# s.py follows which X window is in the foreground and writes one JSON line per
# span of time spent in it: the window's class/title, how long it was focused,
# and the process tree behind it (so a terminal shows whether it was running vim, gdb, ...).
#
# It is event driven: the window manager sets _NET_ACTIVE_WINDOW on the root
# window whenever focus moves, and the focused window's title changes when e.g.
# an editor switches files, so we listen for PropertyNotify on both.
# Time with no keyboard/mouse input for IDLE_AFTER seconds is not counted.
import json
import os
import select
import signal
import sys
import time

from Xlib import X, display, error

IDLE_AFTER = 300
# focus passes through no window at all for a few ms on every switch
MIN_SPAN = 0.5
POLL = 10


def process_tree(pid):
    try:
        node = {
            'pid': pid,
            'comm': open(f'/proc/{pid}/comm').read().strip(),
            'exe': os.readlink(f'/proc/{pid}/exe'),
            'cmdline': open(f'/proc/{pid}/cmdline').read().strip('\0').split('\0'),
        }
        children = open(f'/proc/{pid}/task/{pid}/children').read().split()
    except OSError:
        return None
    children = [c for c in (process_tree(int(c)) for c in children) if c]
    if children:
        node['children'] = children
    return node


class Tracker:
    def __init__(self, out):
        self.out = out
        self.d = display.Display()
        self.root = self.d.screen().root
        self.atom = {n: self.d.intern_atom(n) for n in (
            '_NET_ACTIVE_WINDOW', '_NET_WM_NAME', '_NET_WM_PID', 'WM_NAME', 'UTF8_STRING')}
        self.root.change_attributes(event_mask=X.PropertyChangeMask)
        self.window = None
        self.span = None
        self.idle = False
        self.focus_changed()

    def prop(self, win, name, type=X.AnyPropertyType):
        p = win.get_full_property(self.atom[name], type)
        return p.value if p else None

    def active_window(self):
        wid = self.prop(self.root, '_NET_ACTIVE_WINDOW')
        return self.d.create_resource_object('window', wid[0]) if wid is not None and wid[0] else None

    def describe(self, win):
        if win is None:
            return {}
        try:
            title = self.prop(win, '_NET_WM_NAME', self.atom['UTF8_STRING']) or self.prop(win, 'WM_NAME') or b''
            info = {'title': title.decode('utf-8', 'replace') if isinstance(title, bytes) else title}
            if wm_class := win.get_wm_class():
                info['instance'], info['class'] = wm_class
            if pid := self.prop(win, '_NET_WM_PID'):
                info['pid'] = int(pid[0])
                info['process'] = process_tree(info['pid'])
            return info
        except error.XError:
            # the window went away between the event and us asking about it
            return {}

    def close_span(self, end):
        span, self.span = self.span, None
        if span and end - span['start'] >= MIN_SPAN:
            self.out.write(json.dumps({**span, 'end': end, 'seconds': round(end - span['start'], 3)}) + '\n')
            self.out.flush()

    def open_span(self, start, info=None):
        self.close_span(start)
        if not self.idle:
            self.span = {'start': start, **(info if info is not None else self.describe(self.window))}

    def focus_changed(self):
        new = self.active_window()
        if (new and new.id) == (self.window and self.window.id):
            return
        if self.window:
            self.window.change_attributes(event_mask=X.NoEventMask, onerror=lambda *a: None)
        self.window = new
        if self.window:
            self.window.change_attributes(event_mask=X.PropertyChangeMask, onerror=lambda *a: None)
        self.open_span(time.time())

    def check_idle(self):
        idle_for = self.root.screensaver_query_info().idle / 1000
        last_input = time.time() - idle_for
        if not self.idle and idle_for >= IDLE_AFTER:
            self.close_span(last_input)
            self.idle = True
        elif self.idle and idle_for < IDLE_AFTER:
            self.idle = False
            self.open_span(last_input)

    def run(self):
        while True:
            while self.d.pending_events():
                ev = self.d.next_event()
                if ev.type != X.PropertyNotify:
                    continue
                if ev.window == self.root and ev.atom == self.atom['_NET_ACTIVE_WINDOW']:
                    self.focus_changed()
                elif self.window and ev.window == self.window and ev.atom in (self.atom['_NET_WM_NAME'], self.atom['WM_NAME']):
                    info = self.describe(self.window)
                    if self.span and info.get('title') != self.span.get('title'):
                        self.open_span(time.time(), info)
            select.select([self.d], [], [], POLL)
            self.check_idle()


def main():
    out = open(sys.argv[1], 'a') if len(sys.argv) > 1 else sys.stdout
    tracker = None
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))
    try:
        while True:
            # the X server restarts whenever the contestant logs out, so keep reconnecting
            try:
                tracker = Tracker(out)
                tracker.run()
            except (error.DisplayError, error.ConnectionClosedError, ConnectionError):
                if tracker:
                    tracker.close_span(time.time())
                tracker = None
                time.sleep(5)
    finally:
        if tracker:
            tracker.close_span(time.time())


if __name__ == '__main__':
    main()
