# waybar/.config/waybar/scripts/fedora_updates.py

#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ---- knobs (override via env) ----
TTL_MIN = int(os.environ.get("UPDATES_TTL_MIN", "30"))  # refresh cache every N minutes
SHOW_ZERO = (
    os.environ.get("UPDATES_SHOW_ZERO", "0") == "1"
)  # show "0" instead of hiding
ICON = os.environ.get("UPDATES_ICON", "")  # Nerd Font wrench

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
CACHE = Path(RUNTIME_DIR) / "fedora_updates.cache.json"


def cmd_exists(c: str) -> bool:
    return shutil.which(c) is not None


def run(cmd):
    return subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
    )


def count_dnf_updates():
    # Prefer dnf5 if available, else dnf
    dnf = "dnf5" if cmd_exists("dnf5") else "dnf"
    # Fast and parseable: list only upgradable packages
    # -q: quiet; list --upgrades prints table-like lines after the header
    res = run([dnf, "-q", "list", "--upgrades"])
    if res.returncode not in (
        0,
        100,
    ):  # 100 can be "updates available" for some dnf ops
        return None
    lines = res.stdout.splitlines()
    # Skip header lines; count rows that look like: "pkg.arch version repo"
    cnt = 0
    for ln in lines:
        ln = ln.strip()
        if (
            not ln
            or ln.lower().startswith("last metadata")
            or ln.lower().startswith("available upgrades")
        ):
            continue
        # crude but effective: at least 3 columns separated by spaces
        if len(re.split(r"\s+", ln)) >= 3:
            cnt += 1
    return cnt


def count_rpm_ostree_updates():
    # rpm-ostree upgrade --check returns JSON-ish lines on newer versions
    res = run(["rpm-ostree", "upgrade", "--check"])
    if res.returncode not in (0, 77):  # 77 may mean no updates in some versions
        return None
    out = res.stdout.strip()
    # Simple heuristic: count "AvailableUpdate" lines or fallback to "updates:" counts if present
    m = re.search(
        r"AvailableUpdate.*?packages?:\s*(\d+)", out, re.IGNORECASE | re.DOTALL
    )
    if m:
        return int(m.group(1))
    # Fallback: if output contains "No updates available", return 0
    if "No updates" in out or "no updates" in out:
        return 0
    # As a last resort, say 0 if empty
    return 0 if not out else None


def read_cache():
    if CACHE.exists():
        age = time.time() - CACHE.stat().st_mtime
        if age <= TTL_MIN * 60:
            try:
                return json.loads(CACHE.read_text())
            except Exception:
                pass
    return None


def write_cache(payload):
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = str(CACHE) + ".tmp"
        Path(tmp).write_text(json.dumps(payload) + "\n")
        os.replace(tmp, CACHE)
    except Exception:
        pass


def main():
    # try cache first
    cached = read_cache()
    if cached is not None:
        print(json.dumps(cached), flush=True)
        return 0

    # detect rpm-ostree vs dnf
    if Path("/run/ostree-booted").exists() and cmd_exists("rpm-ostree"):
        count = count_rpm_ostree_updates()
    else:
        count = count_dnf_updates()

    if count is None:
        # error state; don't spam the bar
        payload = {"text": "", "class": "updates-error"}
        print(json.dumps(payload), flush=True)
        return 0

    if count == 0 and not SHOW_ZERO:
        payload = {"text": "", "class": "updates-0"}
    else:
        payload = {
            "text": f"{ICON} {count}",
            "class": f"updates-{count and 'has' or '0'}",
        }

    write_cache(payload)
    print(json.dumps(payload), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
