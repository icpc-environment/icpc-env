#!/icpc/scripts/venv/bin/python
"""The contestant's backup app: where to email a copy of the team's files after
the contest, and a button to back up now. The work is done as root by
/icpc/scripts/icpc-backup, through sudo."""
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import FreeSimpleGUI as sg

sys.path.insert(0, "/icpc/scripts")
import icpcconfig

BACKUP = "/icpc/scripts/icpc-backup"
SETTINGS = Path("/var/lib/icpc-backup/settings.json")
STATUS = Path("/run/icpc-backup/status.json")
MAX_EMAILS = 3
# Bump whenever the notice's meaning changes; saved with the team's consent
NOTICE_VERSION = 1


def notice(contact, retention_days):
    ask = f" Questions, or to withdraw some other way: {contact}." if contact else ""
    return f"""Privacy notice (version {NOTICE_VERSION})

During the contest, the files in your home folder (up to 1 MB each, not hidden files) and your printouts are backed up to the contest's management server, so your work can be recovered if this machine fails. That happens whether or not you fill anything in here.

If you want a copy of those files after the contest, enter up to {MAX_EMAILS} email addresses. If you do:
  - We store the addresses with your team's name and id, and use them only to email you a link to download your files.
  - The link and the addresses are deleted {retention_days} days after the files are released.
  - You can withdraw at any time by clearing the addresses here and pressing Save.{ask}"""


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def local_time(iso):
    try:
        return datetime.fromisoformat(iso).astimezone().strftime("%H:%M:%S")
    except (TypeError, ValueError):
        return None


def status_text():
    status = read_json(STATUS) or {}
    last = local_time(status.get("last_success"))
    lines = [f"Last backup: {last}" if last else "Last backup: none yet"]
    requested = status.get("requested_at")
    if requested and (not status.get("last_success") or requested > status["last_success"]):
        lines.append(f"Backup requested at {local_time(requested)}, waiting for the server")
    if status.get("skipped_count"):
        names = ", ".join(s["path"] for s in status.get("skipped", [])[:3])
        more = "..." if status["skipped_count"] > 3 else ""
        lines.append(f"Left out, over 1 MB: {names}{more}")
    return "\n".join(lines)


def backup(*args, data=None):
    p = subprocess.run(["sudo", "-n", BACKUP, *args], input=data, capture_output=True, text=True, timeout=30)
    return p.returncode, (p.stdout + p.stderr).strip()


def main():
    config = icpcconfig.load()
    settings = config.get("backup") or {}
    sg.theme("Default1")
    if not settings.get("enabled"):
        sg.popup("Backups aren't enabled on this machine.", title="Backups")
        return

    saved = read_json(SETTINGS) or {}
    emails = saved.get("emails", []) + [""] * MAX_EMAILS
    team = Path("/icpc/TEAM").read_text().strip() if Path("/icpc/TEAM").exists() else "No team set"

    layout = [
        [sg.Text("Backups", font=("Helvetica", 16))],
        [sg.Text(team)],
        [sg.Multiline(notice(settings.get("contact"), settings.get("retention_days", 30)),
                      size=(80, 14), disabled=True, no_scrollbar=True)],
        [sg.Text(f"Email a copy of our files to (up to {MAX_EMAILS}):")],
        *[[sg.Input(emails[i], key=f"email{i}", size=(50, 1))] for i in range(MAX_EMAILS)],
        [sg.Checkbox("We agree to these addresses being stored and used as described above",
                     key="consent", default=bool(saved.get("consent")))],
        [sg.Button("Save"), sg.Button("Back up now"), sg.Button("Close")],
        [sg.Text(status_text(), key="status", size=(80, 3))],
    ]
    window = sg.Window("Backups", layout, finalize=True)

    while True:
        event, values = window.read(timeout=5000)
        if event in (sg.WIN_CLOSED, "Close"):
            break
        if event == "Save":
            addresses = [values[f"email{i}"].strip() for i in range(MAX_EMAILS) if values[f"email{i}"].strip()]
            if addresses and not values["consent"]:
                sg.popup("Tick the box to agree before saving email addresses.", title="Backups")
                continue
            if addresses:
                question = "Email a copy of your files to:\n\n" + "\n".join(addresses) + "\n\nIs that right?"
            else:
                question = "Remove all email addresses? You won't be sent a copy of your files."
            if sg.popup_yes_no(question, title="Backups") != "Yes":
                continue
            rc, out = backup("settings", data=json.dumps({
                "emails": addresses, "consent": bool(values["consent"]), "notice_version": NOTICE_VERSION}))
            sg.popup("Saved." if rc == 0 else f"Couldn't save: {out}", title="Backups")
        if event == "Back up now":
            window["Back up now"].update(disabled=True)
            window.perform_long_operation(lambda: backup("request"), "requested")
        if event == "requested":
            rc, out = values["requested"]
            window["Back up now"].update(disabled=False)
            if rc != 0:
                sg.popup(f"Couldn't ask for a backup: {out}", title="Backups")
        window["status"].update(status_text())
    window.close()


if __name__ == "__main__":
    main()
