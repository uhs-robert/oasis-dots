#!/usr/bin/env python3
# cava_waybar.py
# waybar/.config/waybar/scripts/cava_waybar.py
# CAVA → Waybar single-producer + lightweight followers.
# - First instance to grab the lock runs CAVA and writes a shared JSON sink.
# - Other instances just read that file and print it periodically for Waybar.

import os
import sys
import struct
import subprocess
import tempfile
import signal
import json
import time
import ctypes

# ── Env knobs ───────────────────────────────────────────────────────────────
BARS = int(os.environ.get("CAVA_BARS", "40"))
BIT_FORMAT = os.environ.get("CAVA_BIT", "16bit")  # "8bit" | "16bit"
SENS = int(os.environ.get("CAVA_SENS", "150"))
CHANNELS = os.environ.get("CAVA_CHANNELS", "mono")  # "mono" | "stereo"
METHOD = os.environ.get("CAVA_INPUT", "pulse")
CLASS_NAME = os.environ.get("CAVA_CLASS", "cava")
COLOR_HEX = os.environ.get("CAVA_COLOR", "#2E2620")
# GAP = "\u200a"  # hair space: ultra thin

STYLE_NAME = os.environ.get(
    "CAVA_STYLE", "blocks"
)  # blocks|braille|dots|tri|shades|ticks|wave
GAP = os.environ.get("CAVA_GAP", "\u200a")  # " ", "│", "·", etc.
BORDER = os.environ.get("CAVA_BORDER", "none")  # none|pipe|bracket
MARKUP = os.environ.get("CAVA_MARKUP", "0") == "1"  # pango span color

FPS = int(os.environ.get("CAVA_FPS", "12"))  # producer emit cap
FOLLOW_INT = float(
    os.environ.get("CAVA_FOLLOWER_INTERVAL", "1")
)  # follower print period (s)

# Runtime dir for user
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SINK_PATH = os.environ.get("CAVA_SINK", f"{RUNTIME_DIR}/cava_waybar.json")
LOCK_PATH = os.environ.get("CAVA_LOCK", f"{RUNTIME_DIR}/cava_waybar.lock")

# ── Styles (low→high intensity) ─────────────────────────────────────────────
STYLES = {
    "blocks": list("▁▂▃▄▅▆▇█"),
    "braille": list("⡀⡄⣆⣇⣧⣷⣿"),
    "dots": list("·•●◉"),
    "tri": list("△▲"),
    "shades": list("░▒▓█"),
    "ticks": ["", "|", "||", "|||", "||||", "|||||"],
    "wave": list(" _-^"),
}
GLYPHS = STYLES.get(STYLE_NAME, STYLES["blocks"])

# Bit depth mapping
if BIT_FORMAT == "16bit":
    BYTETYPE, BYTESIZE, MAXV = "H", 2, 65535
else:
    BYTETYPE, BYTESIZE, MAXV = "B", 1, 255

STOP = False


def _stop(*_a):
    global STOP
    STOP = True


# global signal setup
signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)
try:
    signal.signal(signal.SIGPIPE, _stop)  # exit if Waybar closes our pipe
except Exception:
    pass


def wrap_token(tok: str) -> str:
    if BORDER == "pipe":
        return f"│{tok}│"
    if BORDER == "bracket":
        return f"[{tok}]"
    return tok


def val_to_token(v: int) -> str:
    idx = round((v / MAXV) * (len(GLYPHS) - 1))
    if idx < 0:
        idx = 0
    if idx >= len(GLYPHS):
        idx = len(GLYPHS) - 1
    return GLYPHS[idx]


def atomic_write(path: str, text: str) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w") as f:
        f.write(text)
        f.write("\n")
    os.replace(tmp, path)


def try_lock(path: str):
    """Return a file object with exclusive non-blocking lock, or None if taken."""
    import fcntl

    os.makedirs(os.path.dirname(path), exist_ok=True)
    f = open(path, "w")
    try:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        f.write(str(os.getpid()))
        f.flush()
        return f
    except BlockingIOError:
        f.close()
        return None


# Cache the probe a bit to avoid spamming playerctl
_last_check = 0.0
_last_active = False


def is_media_active():
    """
    True if any MPRIS player reports Playing or Paused.
    False if no players or only Stopped.
    """
    global _last_check, _last_active
    now = time.monotonic()
    if now - _last_check < 0.3:
        return _last_active
    _last_check = now
    try:
        # -a = all players; returns one status per player
        lines = (
            subprocess.check_output(
                ["playerctl", "-a", "status"], stderr=subprocess.DEVNULL
            )
            .decode()
            .splitlines()
        )
        states = {ln.strip().lower() for ln in lines if ln.strip()}
        _last_active = any(s in ("playing", "paused") for s in states)
    except Exception:
        _last_active = False
    return _last_active


def install_parent_death_sig(sig=signal.SIGTERM):
    """
    Ask the kernel to send us (or our child, when used in preexec_fn)
    SIGTERM if our parent (Waybar) dies. Linux-only.
    """
    try:
        libc = ctypes.CDLL("libc.so.6")
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, int(sig))
    except Exception:
        pass


def safe_write_line(obj) -> bool:
    """Write one JSON line to stdout; return False if the pipe is gone."""
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
        return True
    except BrokenPipeError:
        return False


def producer(lock_file):
    cava_conf = f"""
[general]
mode = normal
framerate = 25
lower_cutoff_freq = 50
higher_cutoff_freq = 12000
bars = {BARS}
sensitivity = {SENS}
channels = {CHANNELS}

[input]
method = {METHOD}

[output]
method = raw
raw_target = /dev/stdout
bit_format = {BIT_FORMAT}
channels = {CHANNELS}
mono_option = average

[smoothing]
noise_reduction = 35
integral = 90
gravity = 95
ignore = 2
monstercat = 1.5
""".strip()

    with tempfile.NamedTemporaryFile(mode="w", delete=True) as conf:
        conf.write(cava_conf)
        conf.flush()
        proc = subprocess.Popen(
            ["cava", "-p", conf.name],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            preexec_fn=install_parent_death_sig,  # make child die when we do
        )

        out = proc.stdout
        if out is None:
            return 1

        last_emit = 0.0
        chunk = BYTESIZE * BARS
        fmt = BYTETYPE * BARS

        try:
            atomic_write(SINK_PATH, json.dumps({"text": "", "class": CLASS_NAME}))
        except Exception:
            pass

        while not STOP:
            buf = out.read(chunk)
            if not buf or len(buf) < chunk:
                break

            now = time.monotonic()
            if now - last_emit < 1.0 / max(FPS, 1):
                continue
            last_emit = now

            vals = struct.unpack(fmt, buf)
            tokens = [val_to_token(v) for v in vals]
            text = GAP.join(tokens)

            payload = {"text": text if is_media_active() else "", "class": CLASS_NAME}

            try:
                atomic_write(SINK_PATH, json.dumps(payload))
            except Exception:
                pass

            if not safe_write_line(payload):  # Waybar closed pipe
                break

        # Terminate AFTER the loop
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    return 0


def follower():
    last_mtime = 0.0
    last_payload = None
    sleep_s = max(0.002, 0.5 / max(FPS, 1))  # poll ~2x producer FPS

    # Always print one line immediately
    try:
        with open(SINK_PATH, "r") as f:
            line = f.readline().strip()
            last_payload = (
                json.loads(line) if line else {"text": "", "class": CLASS_NAME}
            )
    except Exception:
        last_payload = {"text": "", "class": CLASS_NAME}
    if not safe_write_line(last_payload):
        return 0

    while not STOP:
        try:
            st = os.stat(SINK_PATH)
            if st.st_mtime != last_mtime:
                last_mtime = st.st_mtime
                with open(SINK_PATH, "r") as f:
                    line = f.readline().strip()
                if line:
                    payload = json.loads(line)
                    if payload != last_payload:
                        last_payload = payload
                        out = (
                            payload
                            if is_media_active()
                            else {"text": "", "class": CLASS_NAME}
                        )
                        if not safe_write_line(out):
                            break
        except FileNotFoundError:
            pass
        except Exception:
            pass

        time.sleep(sleep_s)

    return 0


def main():
    install_parent_death_sig()  # if Waybar (our parent) dies, we get SIGTERM
    # Decide role
    lock_file = try_lock(LOCK_PATH)
    if lock_file is not None:
        return producer(lock_file)
    else:
        return follower()


if __name__ == "__main__":
    raise SystemExit(main())
