"""Write one JSON line per task (name, file:line, statuses, seconds) to $VM_TIMING_LOG.

Enabled by `just vm ansible`; summarised by `just vm timings`.
"""
import json
import os
import time

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "timing"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        path = os.environ.get("VM_TIMING_LOG")
        self.out = open(path, "w", buffering=1) if path else None
        self.current = None

    def _finish(self):
        if self.current and self.out:
            task, start, statuses = self.current
            self.out.write(json.dumps({
                "name": task.get_name(),
                "path": task.get_path(),
                "statuses": sorted(statuses),
                "seconds": round(time.monotonic() - start, 2),
            }) + "\n")
        self.current = None

    def _start(self, task):
        self._finish()
        self.current = (task, time.monotonic(), set())

    def _status(self, status):
        if self.current:
            self.current[2].add(status)

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._start(task)

    def v2_playbook_on_handler_task_start(self, task):
        self._start(task)

    def v2_runner_on_ok(self, result):
        self._status("changed" if result._result.get("changed") else "ok")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._status("ignored" if ignore_errors else "failed")

    def v2_runner_on_skipped(self, result):
        self._status("skipped")

    def v2_runner_on_unreachable(self, result):
        self._status("unreachable")

    def v2_playbook_on_stats(self, stats):
        self._finish()
