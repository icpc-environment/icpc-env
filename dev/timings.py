#!/usr/bin/env python3
"""Summarise a timing.jsonl written by dev/callback_plugins/timing.py.

  timings.py <timing.jsonl> [top N]
"""
import collections
import json
import os
import sys


def main(path, top=25):
    tasks = [json.loads(line) for line in open(path)]
    for t in tasks:
        t["path"] = os.path.relpath(t["path"])
    total = sum(t["seconds"] for t in tasks)
    by_file = collections.Counter()
    for t in tasks:
        by_file[t["path"].rsplit(":", 1)[0]] += t["seconds"]

    print(f"{total / 60:.1f} min over {len(tasks)} tasks\n\nBy file:")
    for f, s in by_file.most_common():
        if s >= 1:
            print(f"  {s:7.0f}s  {s / total:4.0%}  {f}")
    print(f"\nSlowest {top} tasks:")
    for t in sorted(tasks, key=lambda t: -t["seconds"])[:top]:
        print(f"  {t['seconds']:7.0f}s  {t['name']}  ({t['path']}, {','.join(t['statuses']) or 'no hosts'})")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 25)
