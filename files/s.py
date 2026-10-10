#!/usr/bin/env python3
# s.py spies on users to see what their active x window is, collects some information about it and dumps it to stdout.
#!/usr/bin/env python3
import subprocess
import os
import json
import time
from pathlib import Path

# TODO: update this to use xlib, and actively monitor for changes, writing out a log (with app durations)
# https://stackoverflow.com/questions/60141048/get-notifications-when-active-x-window-changes-using-python-xlib
# we can then also measure fun things like context switches/habits/etc
# Maybe even turn things into traces?
# /run is tmpfs, lets write things there

def get_process_children(pid):
    # Define a recursive function to find children of the given PID
    def find_children(ppid):
        childs = []
        try:
            # Read the contents of the /proc/<pid>/task/<pid>/children file
            with open(f'/proc/{ppid}/task/{ppid}/children') as children_file:
                children = children_file.read().strip().split()
                for child in children:
                    child_pid = int(child)
                    childs.append(find_children(child_pid))
        except (FileNotFoundError, PermissionError):
            # Skip processes that cannot be accessed
            pass

        ret = {
            'exe': os.readlink(f'/proc/{ppid}/exe'),
            'cmdline': Path(f'/proc/{ppid}/cmdline').read_text().strip('\u0000').split('\u0000'),
            'comm': Path(f'/proc/{ppid}/comm').read_text().strip(),
            'pid': ppid,
        }
        if len(childs) > 0:
            ret['children'] = childs
        return ret
    # Call the recursive function to populate the process_children list
    return find_children(pid)

# Use xprop to get the foreground window and some info about it
result = subprocess.run([
    '/bin/bash', '-c',
    'xprop -notype -id $(xprop -root -f _NET_ACTIVE_WINDOW 0x " \$0\\n" _NET_ACTIVE_WINDOW 2>/dev/null | awk "{print \$2}") WM_NAME WM_CLASS WM_WINDOW_ROLE _NET_WM_PID 2>/dev/null'
    ], stdout=subprocess.PIPE)

if result.returncode != 0:
    print(json.dumps({"error": "failed to find active window", "ts": int(time.time())}))
    exit(1)
result = result.stdout.decode('utf-8').strip()

# Remap the info we get from xprop
MAPPING={
    "WM_NAME": "name",
    "_NET_WM_PID": "pid",
    "WM_WINDOW_ROLE": "window_role",
    "WM_CLASS": "window_class"
}
# Parse the xprop info, remap it, and split/extract it into a pretty hash
info = {MAPPING.get(i.split(' = ')[0],i.split(' = ')[0]): i.split(' = ')[1].strip('"') for i in result.split('\n') if '=' in i}
# get the children/process info of the active window (so we can tell e.g. if they're running vim inside bash)
info['process'] = get_process_children(info["pid"])
# Add the current timestamp
info['ts'] = int(time.time())

print(json.dumps(info, indent=2))
