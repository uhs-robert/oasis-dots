#!/usr/bin/env python3
# media_waybar.py
# waybar/.config/waybar/scripts/media_waybar.py
# CAVA producer/follower + MPRIS metadata for Waybar.

import os, sys, struct, subprocess, tempfile, signal, json, time, ctypes

# ── Env knobs ───────────────────────────────────────────────────────────────
TITLE_MAX = int(os.environ.get("TITLE_MAX", "23"))
MARQUEE = os.environ.get("MARQUEE", "1") == "0"
MARQUEE_SPEED = float(os.environ.get("MARQUEE_SPEED", "2"))  # chars per second
MARQUEE_GAP = os.environ.get("MARQUEE_GAP", "   ")
BARS = int(os.environ.get("CAVA_BARS", "40"))
BIT_FORMAT = os.environ.get("CAVA_BIT", "16bit")  # "8bit" | "16bit"
SENS = int(os.environ.get("CAVA_SENS", "150"))
CHANNELS = os.environ.get("CAVA_CHANNELS", "mono")  # "mono" | "stereo"
METHOD = os.environ.get("CAVA_INPUT", "pulse")
CLASS_NAME = os.environ.get("CAVA_CLASS", "cava")
COLOR_HEX = os.environ.get("CAVA_COLOR", "#2E2620")
STYLE_NAME = os.environ.get("CAVA_STYLE", "blocks")
GAP = os.environ.get("CAVA_GAP", "\u200a")
BORDER = os.environ.get("CAVA_BORDER", "none")  # none|pipe|bracket
MARKUP = os.environ.get("CAVA_MARKUP", "0") == "1"
FPS = int(os.environ.get("CAVA_FPS", "12"))
FOLLOW_INT = float(os.environ.get("CAVA_FOLLOWER_INTERVAL", "1"))
ELLIPSIS = "…"

# Show bars? show title/artist? tweak here
SHOW_BARS = os.environ.get("SHOW_BARS", "1") == "1"
SHOW_ARTIST = os.environ.get("SHOW_ARTIST", "1") == "1"

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SINK_PATH = os.environ.get("CAVA_SINK", f"{RUNTIME_DIR}/cava_waybar.json")
LOCK_PATH = os.environ.get("CAVA_LOCK", f"{RUNTIME_DIR}/cava_waybar.lock")

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

if BIT_FORMAT == "16bit":
    BYTETYPE, BYTESIZE, MAXV = "H", 2, 65535
else:
    BYTETYPE, BYTESIZE, MAXV = "B", 1, 255

STOP = False


def _stop(*_a):
    global STOP
    STOP = True


signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)
try:
    signal.signal(signal.SIGPIPE, _stop)
except Exception:
    pass


def _pango_escape(s: str) -> str:
    if not s:
        return s
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


_marquee_state = {
    "last_src": "",
    "t0": 0.0,  # time origin for this src
}


def _marquee(text: str) -> str:
    """
    Time-based marquee: offset = floor((now - t0) * MARQUEE_SPEED).
    Looks steady regardless of how often we print.
    """
    if not text:
        _marquee_state["last_src"] = ""
        _marquee_state["t0"] = 0.0
        return ""

    if not MARQUEE or TITLE_MAX <= 0 or len(text) <= TITLE_MAX:
        # reset origin so when it grows long again we start from 0
        _marquee_state["last_src"] = text
        _marquee_state["t0"] = time.monotonic()

        if len(text) <= TITLE_MAX or TITLE_MAX <= 1:
            # fits already, or not enough room to show ellipsis meaningfully
            return text[:TITLE_MAX]

        # leave room for the tiny ellipsis
        return text[: TITLE_MAX - 1] + ELLIPSIS

    base = text + MARQUEE_GAP
    now = time.monotonic()

    if text != _marquee_state["last_src"]:
        _marquee_state["last_src"] = text
        _marquee_state["t0"] = now

    # chars scrolled since t0
    offset = int((now - _marquee_state["t0"]) * max(MARQUEE_SPEED, 0.1)) % len(base)

    end = offset + TITLE_MAX
    if end <= len(base):
        return base[offset:end]
    # wrap
    return base[offset:] + base[: (end - len(base))]


def _list_players():
    try:
        out = (
            subprocess.check_output(["playerctl", "-l"], stderr=subprocess.DEVNULL)
            .decode()
            .splitlines()
        )
        return [p.strip() for p in out if p.strip()]
    except Exception:
        return []


def _player_status(name: str) -> str:
    try:
        return (
            subprocess.check_output(
                ["playerctl", "-p", name, "status"], stderr=subprocess.DEVNULL
            )
            .decode()
            .strip()
        )
    except Exception:
        return ""


def _pick_active_player():
    """
    Prefer a player that is Playing, else Paused. Return player name or ''.
    """
    players = _list_players()
    if not players:
        return ""
    playing = [p for p in players if _player_status(p).lower() == "playing"]
    if playing:
        return playing[0]
    paused = [p for p in players if _player_status(p).lower() == "paused"]
    return paused[0] if paused else players[0]


def _fmt_time_secs(us_or_s):
    if us_or_s in (None, "", 0):
        return "--:--"
    try:
        x = float(us_or_s)
    except Exception:
        return "--:--"
    # auto-detect microseconds vs seconds
    if x > 1e6:
        x = x / 1_000_000.0
    secs = max(0, int(x))
    h, r = divmod(secs, 3600)
    m, s = divmod(r, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:d}:{s:02d}"


def wrap_token(tok: str) -> str:
    if BORDER == "pipe":
        return f"│{tok}│"
    if BORDER == "bracket":
        return f"[{tok}]"
    return tok


def val_to_token(v: int) -> str:
    idx = round((v / MAXV) * (len(GLYPHS) - 1))
    idx = max(0, min(idx, len(GLYPHS) - 1))
    return GLYPHS[idx]


def atomic_write(path: str, text: str) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w") as f:
        f.write(text)
        f.write("\n")
    os.replace(tmp, path)


def try_lock(path: str):
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


# ── MPRIS / playerctl helpers ──────────────────────────────────────────────
_last_check = 0.0
_last_active = False
_meta_cache_t = 0.0
_meta_cache = None


def is_media_active():
    global _last_check, _last_active
    now = time.monotonic()
    if now - _last_check < 0.25:
        return _last_active
    _last_check = now
    try:
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


def get_media_info():
    """
    Returns fields for the SINGLE chosen player (not playerctld):
      title, artist, album, status, player, position_s, length_s
    """
    global _meta_cache_t, _meta_cache
    now = time.monotonic()
    if now - _meta_cache_t < 0.5 and _meta_cache is not None:
        return _meta_cache

    name = _pick_active_player()
    if not name:
        _meta_cache = {
            "title": "",
            "artist": "",
            "album": "",
            "status": "",
            "player": "",
            "position_s": None,
            "length_s": None,
        }
        _meta_cache_t = now
        return _meta_cache

    base = ["playerctl", "-p", name]

    def _fmt(fmt):
        try:
            return (
                subprocess.check_output(
                    base + ["metadata", f"--format={fmt}"], stderr=subprocess.DEVNULL
                )
                .decode()
                .strip()
            )
        except Exception:
            return ""

    # status, timing
    status = _player_status(name)
    try:
        pos_out = (
            subprocess.check_output(base + ["position"], stderr=subprocess.DEVNULL)
            .decode()
            .strip()
        )
        position_s = float(pos_out) if pos_out else None
    except Exception:
        position_s = None

    # mpris:length is microseconds; {{mpris:length}} via --format is reliable
    length_raw = _fmt("{{mpris:length}}")
    try:
        length_s = int(length_raw) if length_raw.isdigit() else None
    except Exception:
        length_s = None

    # Prefer Identity (true app name); fall back to playerName
    identity = _fmt("{{mpris:identity}}") or _fmt("{{playerName}}")

    info = {
        "title": _fmt("{{title}}"),
        "artist": _fmt("{{artist}}"),
        "album": _fmt("{{album}}"),
        "player": identity or name,  # e.g. "firefox", "Spotify"
        "status": status,  # Playing | Paused | Stopped | ""
        "position_s": position_s,
        "length_s": length_s,
    }
    _meta_cache = info
    _meta_cache_t = now
    return info


def install_parent_death_sig(sig=signal.SIGTERM):
    try:
        libc = ctypes.CDLL("libc.so.6")
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, int(sig))
    except Exception:
        pass


def safe_write_line(obj) -> bool:
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
        return True
    except BrokenPipeError:
        return False


# ── Rendering ───────────────────────────────────────────────────────────────
def render_payload(bars_text: str):
    active = is_media_active()
    meta = (
        get_media_info()
        if active
        else {"title": "", "artist": "", "album": "", "status": "", "player": ""}
    )

    # Transport icons
    pause_icon = "<span size='12000' color='#1CA0FD'></span>"
    play_icon = "<span size='12000' color='peru'></span>"
    playpause_icon = (
        pause_icon if meta.get("status", "").lower() == "playing" else play_icon
    )

    # Title line
    title = meta.get("title", "").strip()
    artist = meta.get("artist", "").strip()
    if title:
        if SHOW_ARTIST and artist:
            title_text = f"{title} — {artist}"
        else:
            title_text = title
    else:
        title_text = ""

    visible_title = _marquee(title_text)
    visible_title = _pango_escape(visible_title)
    title_text = _pango_escape(title_text)
    bars_text = _pango_escape(bars_text)
    bars_text = f"<span size='7000' color='#1CA0FD'>{bars_text}</span>"

    left = f"{playpause_icon}"
    parts = []
    if left:
        parts.append(left)
    if visible_title:
        parts.append(visible_title)
    if SHOW_BARS and bars_text:
        parts.append(bars_text)

    text = "  ".join(parts).strip()

    # Build tooltip (escaped)
    tooltip_lines = []

    t_title = _pango_escape(meta.get("title", ""))
    t_artist = _pango_escape(meta.get("artist", ""))
    t_album = _pango_escape(meta.get("album", ""))

    pos_str = _fmt_time_secs(meta.get("position_s"))
    len_str = _fmt_time_secs(meta.get("length_s"))

    app = meta.get("player", "")
    status = meta.get("status", "").lower()
    app_status = _pango_escape(f"{app} ({status})") if (app or status) else ""

    if app_status:
        tooltip_lines.append(app_status)
    if t_title:
        tooltip_lines.append(t_title)
    if t_artist:
        tooltip_lines.append(t_artist)
    if t_album:
        tooltip_lines.append(t_album)
    if pos_str != "--:--" or len_str != "--:--":
        tooltip_lines.append(f"{pos_str} / {len_str}")

    tooltip = "\n".join(tooltip_lines) if tooltip_lines else ""
    if not tooltip and title_text:
        tooltip = title_text
    if not tooltip:
        tooltip = " "

    # Hide completely if no media and you prefer that:
    # if not active:
    #     text = ""

    return {
        "text": text,
        "class": CLASS_NAME
        + (" playing" if meta.get("status", "").lower() == "playing" else ""),
        "tooltip": tooltip,
        "alt": meta.get("status", "").lower() or "",
    }


# ── Producer / follower ─────────────────────────────────────────────────────
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
            preexec_fn=install_parent_death_sig,
        )

        out = proc.stdout
        if out is None:
            return 1

        last_emit = 0.0
        chunk = BYTESIZE * BARS
        fmt = BYTETYPE * BARS

        try:
            atomic_write(SINK_PATH, json.dumps(render_payload(bars_text="")))
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
            bars = GAP.join(tokens)
            payload = render_payload(bars_text=bars)

            try:
                atomic_write(SINK_PATH, json.dumps(payload))
            except Exception:
                pass

            if not safe_write_line(payload):
                break

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
    sleep_s = max(0.002, 0.5 / max(FPS, 1))

    # seed from file
    try:
        with open(SINK_PATH, "r") as f:
            line = f.readline().strip()
            baseline = json.loads(line) if line else render_payload("")
    except Exception:
        baseline = render_payload("")
    last_payload = baseline
    if not safe_write_line(last_payload):
        return 0

    while not STOP:
        try:
            st = os.stat(SINK_PATH)
            if st.st_mtime != last_mtime:
                last_mtime = st.st_mtime
                with open(SINK_PATH, "r") as f:
                    line = f.readline().strip()
                src = json.loads(line) if line else {}
                # recompose with fresh metadata
                bars = src.get("text", "")
                # If producer stored full text, try to recover bars by taking the rightmost token group after title;
                # but simpler: rely on SINK bars by re-running render with empty (no double-bake)
                payload = render_payload(bars_text="")
                # prefer producer's bars if present
                if SHOW_BARS and bars:
                    payload = render_payload(bars_text=bars.split("  ")[-1])
                if payload != last_payload:
                    last_payload = payload
                    if not safe_write_line(payload):
                        break
        except FileNotFoundError:
            pass
        except Exception:
            pass

        time.sleep(sleep_s)

    return 0


def main():
    install_parent_death_sig()
    lock_file = try_lock(LOCK_PATH)
    if lock_file is not None:
        return producer(lock_file)
    else:
        return follower()


if __name__ == "__main__":
    raise SystemExit(main())
