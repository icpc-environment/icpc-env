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
