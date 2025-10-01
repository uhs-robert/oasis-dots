#!/usr/bin/env python3
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

# ── Env knobs ───────────────────────────────────────────────────────────────
BARS = int(os.environ.get("CAVA_BARS", "40"))
BIT_FORMAT = os.environ.get("CAVA_BIT", "16bit")  # "8bit" | "16bit"
SENS = int(os.environ.get("CAVA_SENS", "150"))
CHANNELS = os.environ.get("CAVA_CHANNELS", "stereo")  # "mono" | "stereo"
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

# Runtime dir for user (Wayland/Fedora-friendly)
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


def producer(lock_file):
    """Run CAVA, emit at capped FPS, write sink atomically, also stream to stdout."""
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    cava_conf = f"""
[general]
bars = {BARS}
sensitivity = {SENS}
channels = {CHANNELS}

[input]
method = {METHOD}

[output]
method = raw
raw_target = /dev/stdout
bit_format = {BIT_FORMAT}
""".strip()

    with tempfile.NamedTemporaryFile(mode="w", delete=True) as conf:
        conf.write(cava_conf)
        conf.flush()
        proc = subprocess.Popen(
            ["cava", "-p", conf.name], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )

        out = proc.stdout
        if out is None:
            return 1

        last_emit = 0.0
        chunk = BYTESIZE * BARS
        fmt = BYTETYPE * BARS

        # Ensure sink exists early to help followers
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

            if is_media_active():
                payload = {"text": text, "class": CLASS_NAME}
            else:
                payload = {"text": "", "class": CLASS_NAME}  # hide when not playing

            try:
                atomic_write(SINK_PATH, json.dumps(payload))
            except Exception:
                pass

            sys.stdout.write(json.dumps(payload) + "\n")
            sys.stdout.flush()

        try:
            proc.terminate()
        except Exception:
            pass

    # keep lock_file open until exit so we retain the lock
    return 0


def follower():
    """Emit ONLY when the sink file changes; no periodic prints."""
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    last_mtime = 0.0
    last_payload = None
    sleep_s = max(0.002, 0.5 / max(FPS, 1))  # poll ~2x producer FPS, cheap CPU

    # Print one line immediately so Waybar shows something on startup
    try:
        with open(SINK_PATH, "r") as f:
            line = f.readline().strip()
            if line:
                last_payload = json.loads(line)
    except Exception:
        last_payload = {"text": "", "class": CLASS_NAME}
    sys.stdout.write(json.dumps(last_payload) + "\n")
    sys.stdout.flush()

    while not STOP:
        try:
            st = os.stat(SINK_PATH)
            if st.st_mtime != last_mtime:
                last_mtime = st.st_mtime
                with open(SINK_PATH, "r") as f:
                    line = f.readline().strip()
                    if line:
                        payload = json.loads(line)
                        # Only emit if content actually changed (guards tiny mtime skews)
                        if payload != last_payload:
                            last_payload = payload
                            if is_media_active():
                                sys.stdout.write(json.dumps(payload) + "\n")
                            else:
                                sys.stdout.write(
                                    json.dumps({"text": "", "class": CLASS_NAME}) + "\n"
                                )
                            sys.stdout.flush()
        except FileNotFoundError:
            # Producer not up yet; keep previous frame, do not spam
            pass
        except Exception:
            # Ignore partial/invalid reads for this tick
            pass

        time.sleep(sleep_s)

    return 0


def main():
    # Decide role
    lock_file = try_lock(LOCK_PATH)
    if lock_file is not None:
        return producer(lock_file)
    else:
        return follower()


if __name__ == "__main__":
    raise SystemExit(main())
