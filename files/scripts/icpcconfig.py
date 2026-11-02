"""/icpc/config.json, this machine's configuration.

Ansible seeds the build-time settings (contest, management server, ...) and the
setup wizard adds the team, site and printers. /icpc/scripts/icpc-apply makes
the machine match it; nothing else should write the files it generates.
"""
import json
import os
import tempfile
from pathlib import Path

PATH = Path("/icpc/config.json")


def load():
    if not PATH.exists():
        raise SystemExit(f"{PATH} is missing, it's written by ansible when the image is built")
    return json.loads(PATH.read_text())


def save(config):
    # Readers (contestant tools included) must never see a half-written file
    fd, tmp = tempfile.mkstemp(dir=PATH.parent, prefix=".config.json.")
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, PATH)


def lookup(config, key):
    """The value at a dotted key such as "team.name", or KeyError"""
    value = config
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(key)
        value = value[part]
    return value


# config.json's sound setting, as the summary and the setup wizard describe it
SOUND = {"off": "off", "usb": "USB headphones only", "all": "all outputs, speakers too"}


DEFAULT_WALLPAPER = "file:///usr/share/backgrounds/icpc/wallpaper.png"


def on_off(value):
    return "on" if value else "off"


def summary(config):
    """What the machine is configured to do, as (label, description) pairs, for
    the setup wizard and the self test"""
    lines = []
    lines.append(("Timezone", config.get("timezone") or "not set"))
    lines.append(("Paper size", {"a4": "A4", "letter": "Letter"}.get(config.get("papersize"), "Letter")))

    submit = config.get("submit") or {}
    client = submit.get("client") or "none"
    url = submit.get("base_url") or submit.get("pc2_base_url")
    lines.append(("Submit client", f"{client} ({url})" if url else client))

    firefox = "opens at login" if config.get("autostart_firefox", True) else "doesn't open at login"
    homepage = ((config.get("firefox_policies") or {}).get("Homepage") or {}).get("URL")
    lines.append(("Firefox", f"{firefox}, homepage {homepage}" if homepage else firefox))

    sites = sorted(config.get("reverseproxy_sites") or {})
    lines.append(("Allowed sites", ", ".join(sites) if sites else "none"))
    scripts = sorted(config.get("language_scripts") or {})
    lines.append(("Language scripts", ", ".join(scripts) if scripts else "none"))
    lines.append(("Sound", SOUND.get(config.get("sound", "off"), "off")))
    wallpaper = config.get("wallpaper_url")
    lines.append(("Wallpaper", "default" if wallpaper in (None, DEFAULT_WALLPAPER) else wallpaper))

    management = config.get("management") or {}
    if management.get("server") and management.get("fleet"):
        lines.append(("Management", f"{management['server']}, fleet {management['fleet']}, "
                                    f"VPN {on_off(management.get('vpn'))}, "
                                    f"last-minute updates {on_off(management.get('lastminute'))}"))
    else:
        lines.append(("Management", "none"))
    backups = (config.get("backup") or {}).get("enabled")
    lines.append(("Backups", "on, with a log of focused windows and programs run" if backups else "off"))

    keys = len(config.get("ssh_keys") or [])
    certificates = bool(config.get("ssh_user_ca_keys")) and bool(config.get("ssh_principals"))
    lines.append(("Admin ssh", f"{keys} key{'' if keys == 1 else 's'}, "
                               f"certificate login {on_off(certificates)}"))
    return lines
