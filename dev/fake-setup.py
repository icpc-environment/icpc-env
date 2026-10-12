#!/icpc/scripts/venv/bin/python
# Stand in for the first-boot setup wizard on a dev VM: configure a made up team
# and a printer that keeps every job, so the wallpaper, panel, hostname and
# printouts show real team info. Uses the wizard's own apply_* functions from
# /icpc/scripts/icpc_setup. Run via `just vm fake-setup`, as root in the guest.
import importlib.machinery
import importlib.util
import socket
import subprocess
import sys
import time
from pathlib import Path

TEAM = {"id": "999", "name": "ICPC Sysops Team", "affiliation": "ICPC Sysops", "extra": ""}
SITE = "sysops"
PAPERSIZE = "Letter"

# ippeveprinter is CUPS' IPP Everywhere test printer: -k keeps each job in the spool dir,
# -r off skips DNS-SD, since the image has no avahi and it aborts without one
PRINTER_PORT = 8631
PRINTER_SPOOL = "/var/lib/fake-printer"
PRINTER = {
    "group": "dev",
    "uri": f"ipp://localhost:{PRINTER_PORT}/ipp/print",
    "driver": "everywhere",
    "note": "Fake printer (dev/fake-setup.py)",
}


def start_fake_printer():
    Path("/etc/systemd/system/fake-printer.service").write_text(f"""[Unit]
Description=Fake IPP printer that keeps every job in {PRINTER_SPOOL} (dev/fake-setup.py)
Before=cups.service

[Service]
StateDirectory=fake-printer
ExecStart=/usr/sbin/ippeveprinter -r off -k -d {PRINTER_SPOOL} -p {PRINTER_PORT} -n localhost -f application/pdf "Fake Printer"

[Install]
WantedBy=multi-user.target
""")
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "--now", "fake-printer.service"], check=True)
    # lpadmin -m everywhere asks the printer for its capabilities, so it has to be listening first
    deadline = time.monotonic() + 30
    while True:
        try:
            socket.create_connection(("localhost", PRINTER_PORT), timeout=1).close()
            return
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.5)


def load_wizard():
    loader = importlib.machinery.SourceFileLoader("icpc_setup", "/icpc/scripts/icpc_setup")
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


def main():
    start_fake_printer()
    wizard = load_wizard()
    # The wizard reports errors in GUI popups, and there's no display to show them on
    wizard.sg.popup = lambda *args, **kwargs: print(*args, file=sys.stderr)
    wizard.configuration.update({
        "contest": Path("/icpc/CONTEST").read_text().strip(),
        "site": SITE,
        "papersize": PAPERSIZE,
        "print_test_page": False,
        "autostart_firefox": True,
        "delete_printers": True,
        "printers": [PRINTER],
        "team": TEAM,
    })
    wizard.apply_configuration()
    wizard.apply_wallpaper()
    if not wizard.apply_printers():
        raise SystemExit("error: applying the printers failed")
    Path("/icpc/setup-complete").write_text(SITE + "\n")
    print(f"Configured team {TEAM['id']} - {TEAM['name']} ({TEAM['affiliation']}) at site {SITE}")


if __name__ == "__main__":
    main()
