#!/usr/bin/env bash
# shellcheck disable=SC2154
# Shared by the *-audio importers; source it after set -euo pipefail. Reads audio_name, rate, out, src, redetect, audio_loop_flags.

# Prints "$audio_name: $1" to stderr and exits 1.
audio_die() {
  echo "$audio_name: $1" >&2
  exit 1
}

audio_require_src() {
  [[ -n $src ]] || audio_die "a source is required (see --help)"
}

# Dies unless every tool named in the arguments is on PATH.
audio_require() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || audio_die "$tool is required"
  done
}

# Dies unless numpy imports; $1 is the python name shown in the message.
audio_require_numpy() {
  python3 -c 'import numpy' 2>/dev/null || audio_die "${1:-python3} numpy is required"
}

# Prints the source's sample rate.
src_rate() {
  ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$1"
}

# Prints "start end" in source samples from the file's loop tags, or nothing.
read_tags() {
  ffprobe -v error -show_entries format_tags:stream_tags -of json "$1" |
    jq -r '[.format.tags, (.streams // [])[].tags] | map(select(. != null)) | add // {} | with_entries(.key |= ascii_upcase)
      | (.LOOPSTART // "" | tonumber? // null) as $s | (.LOOPLENGTH // "" | tonumber? // null) as $l | (.LOOPEND // "" | tonumber? // null) as $e
      | if $s == null then empty elif $l != null then "\($s) \($s + $l)" elif $e != null then "\($s) \($e)" else empty end'
}

# Sets KEY=VALUE tags on $1 without touching its audio: copy with new tags, check the decoded audio is identical, then swap in; an empty value removes the tag.
# OGG keeps Vorbis comments on the stream; FLAC comments and MP3 ID3 TXXX frames are file-level.
write_meta() {
  local file=$1 tmp before after scope='' kv
  local args=()
  shift
  [[ ${file##*.} == ogg ]] && scope=:s:a:0
  for kv in "$@"; do args+=("-metadata$scope" "$kv"); done
  tmp=$(mktemp "$(dirname "$file")/.${audio_name%-audio}-tags.XXXXXX.${file##*.}") || return 1
  if ffmpeg -v error -y -i "$file" -map 0 -c copy -map_metadata 0 "${args[@]}" "$tmp" &&
    before=$(ffmpeg -v error -i "$file" -map 0:a -f md5 -) && after=$(ffmpeg -v error -i "$tmp" -map 0:a -f md5 -) &&
    [[ -n $before && $before == "$after" ]] && touch -r "$file" "$tmp" && mv -f "$tmp" "$file"; then
    return 0
  fi
  rm -f "$tmp"
  echo "$audio_name: could not tag $file; left it untouched" >&2
  return 1
}

# Tags the loop start/end (source samples) into $1.
write_tags() {
  write_meta "$1" LOOPSTART="$2" LOOPLENGTH="$(($3 - $2))" LOOPEND=
}

# Prints the second where a closing fade-out starts: the point after which the 0.5s RMS stays 3 dB under the track's median, walked back along the falling slope.
fade_start() {
  ffmpeg -v error -i "$1" -ac 1 -f f32le - | python3 -c '
import sys
import numpy as np
x = np.frombuffer(sys.stdin.buffer.read(), dtype=np.float32).astype(np.float64)
rate, w, hop = int(sys.argv[1]), int(sys.argv[1]) // 2, int(sys.argv[1]) // 4
env = np.array([20 * np.log10(np.sqrt(np.mean(x[i:i + w] ** 2)) + 1e-9) for i in range(0, max(1, len(x) - w), hop)])
ref = np.median(env[env > -60]) if np.any(env > -60) else 0
tail = np.maximum.accumulate(env[::-1])[::-1] < ref - 3
if not tail.any():
    print(round(len(x) / rate, 3))
    sys.exit()
i = int(np.argmax(tail))
smooth = np.convolve(env, np.ones(4) / 4, mode="same")
floor = max(0, i - 20)
while i > floor and smooth[i - 1] > smooth[i] + 0.05:
    i -= 1
print(round(i * hop / rate, 3))
' "$(src_rate "$1")"
}

# Prints "start end" in the source's own samples from pymusiclooper's best candidate, run on the audio up to 1s before any closing fade.
loop_points() {
  local file=$1 fade dur keep trimmed
  command -v pipx >/dev/null || audio_die "pipx is needed to detect loops; pass $audio_loop_flags instead"
  fade=$(fade_start "$file")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file")
  keep=$(python3 -c "import sys; f, d = map(float, sys.argv[1:]); print(round(max(1.0, f - 1), 3) if f < d - 1 else sys.argv[2])" "$fade" "$dur")
  if [[ $keep != "$dur" ]]; then
    echo "$audio_name: $file fades out from ${fade}s; loop ends are kept before ${keep}s" >&2
  fi
  trimmed=$(mktemp "${TMPDIR:-/tmp}/${audio_name%-audio}-detect.XXXXXX.flac")
  ffmpeg -v error -y -i "$file" -map 0:a -t "$keep" -c:a flac "$trimmed"
  pipx run pymusiclooper export-points --path "$trimmed" --export-to stdout --alt-export-top 1 2>/dev/null |
    awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $1, $2; exit }'
  rm -f "$trimmed"
}

# Prints JSON with the join quality of $2..$3; mode $4 is "full" (tune the length on up to 30s before the fade at $5 seconds, kept only if the spectra agree, then snap), "snap" (move both to a rising zero crossing) or "keep".
refine() {
  ffmpeg -v error -i "$1" -ac 1 -ar "$rate" -f f32le - | python3 -c '
import json, sys
import numpy as np
x = np.frombuffer(sys.stdin.buffer.read(), dtype=np.float32).astype(np.float64)
s, e, rate, mode = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
limit = min(len(x), int(float(sys.argv[5]) * rate))
def spectra(seg, n=2048, hop=512):
    f = np.lib.stride_tricks.sliding_window_view(seg, n)[::hop] * np.hanning(n)
    m = np.log1p(np.abs(np.fft.rfft(f, axis=1))[:, :800])
    m -= m.mean(axis=1, keepdims=True)
    return m / (np.linalg.norm(m, axis=1, keepdims=True) + 1e-9)
def spectral(e):
    w = min(5 * rate, limit - e, len(x) - e)
    return float(np.mean(np.sum(spectra(x[s:s + w]) * spectra(x[e:e + w]), axis=1))) if w >= 2048 else -2.0
pre = max(0, min(10 * rate, s, e - 1503))
post = max(0, min(20 * rate, limit - e - 1503, e - s))
if mode == "full" and pre + post >= 4096:
    a = x[s - pre:s + post]
    def score(d):
        b = x[e + d - pre:e + d + post]
        den = np.sqrt(np.dot(a, a) * np.dot(b, b))
        return float(np.dot(a, b) / den) if len(b) == len(a) and den > 0 else -2.0
    d = max(range(-1500, 1501, 3), key=score)
    d += max(range(-3, 4), key=lambda k: score(d + k))
    if spectral(e + d) >= spectral(e) - 0.005:
        e += d
if mode != "keep":
    for k in sorted(range(-300, 301), key=abs):
        if s + k >= 1 and e + k <= len(x) and x[s + k - 1] <= 0 < x[s + k]:
            s, e = s + k, e + k
            break
def finite(v):
    return round(float(v), 3) if np.isfinite(v) else None
w = min(5 * rate, len(x) - e)
spec = finite(np.mean(np.sum(spectra(x[s:s + w]) * spectra(x[e:e + w]), axis=1))) if w >= 2048 else None
m = min(rate, len(x) - e)
with np.errstate(all="ignore"):
    corr = finite(np.corrcoef(x[s:s + m], x[e:e + m])[0, 1]) if m >= 2 else None
print(json.dumps({"start": s, "end": e, "start_s": round(s / rate, 4), "end_s": round(e / rate, 4), "loop_s": round((e - s) / rate, 4), "spectral_match": spec, "wave_corr": corr}))
' "$2" "$3" "$rate" "$4" "$5"
}

# Prints the gain in dB that brings a track to -18 LUFS without its peak passing -1 dBFS.
music_gain() {
  local stats loud peak
  stats=$(ffmpeg -hide_banner -nostats -i "$1" -af ebur128=peak=sample,volumedetect -f null - 2>&1)
  loud=$(awk '/I:/ { v = $2 } END { print v }' <<<"$stats")
  peak=$(awk '/max_volume:/ { v = $5 } END { print v }' <<<"$stats")
  python3 -c "import sys; print(round(min(-18 - float(sys.argv[1]), -1 - float(sys.argv[2])), 2))" "$loud" "$peak"
}

# Writes samples [from, end) of $1 to $2 with $5 dB of gain, from being $6 or start; the last 60ms crossfade into the audio just before start, so it hands over seamlessly to the loop.
cut_loop() {
  ffmpeg -v error -i "$1" -ar "$rate" -ac 2 -f f32le - | python3 -c '
import sys
import numpy as np
x = np.frombuffer(sys.stdin.buffer.read(), dtype=np.float32).reshape(-1, 2).astype(np.float64)
s, e, gain, f = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[5])
n = min(int(0.06 * int(sys.argv[4])), s, e - s, e - f)
loop = x[f:e].copy()
if n > 0:
    t = np.linspace(0, np.pi / 2, n)[:, None]
    loop[-n:] = loop[-n:] * np.cos(t) + x[s - n:s] * np.sin(t)
sys.stdout.buffer.write((loop * 10 ** (gain / 20)).astype(np.float32).tobytes())
' "$3" "$4" "$5" "$rate" "${6:-$3}" | ffmpeg -v error -y -f f32le -ar "$rate" -ac 2 -i - -c:a libvorbis -q:a 6 -fflags +bitexact -flags:a +bitexact "$2"
}

# Resolves the loop (override, tags or detection), tags the source when the points are new, and prints the loop JSON.
resolve_loop() {
  local file=$1 manual_start=${2:-} manual_end=${3:-} how mode s e sr json
  sr=$(src_rate "$file")
  if [[ -n $manual_start ]]; then
    read -r s e < <(python3 -c "import sys; print(round(float(sys.argv[1]) * $rate), round(float(sys.argv[2]) * $rate))" "$manual_start" "$manual_end")
    how=override mode=snap
  elif ((!redetect)) && read -r s e < <(read_tags "$file") && [[ -n ${s:-} ]]; then
    read -r s e < <(python3 -c "import sys; r = $rate / int(sys.argv[3]); print(round(int(sys.argv[1]) * r), round(int(sys.argv[2]) * r))" "$s" "$e" "$sr")
    how=tags mode=keep
  else
    read -r s e < <(loop_points "$file")
    read -r s e < <(python3 -c "import sys; r = $rate / int(sys.argv[3]); print(round(int(sys.argv[1]) * r), round(int(sys.argv[2]) * r))" "$s" "$e" "$sr")
    how=detected mode=full
  fi
  json=$(refine "$file" "$s" "$e" "$mode" "$(fade_start "$file")")
  if [[ $how != tags ]]; then
    read -r s e < <(jq -r --argjson r "$(python3 -c "print(int($sr) / $rate)")" '"\(.start * $r | round) \(.end * $r | round)"' <<<"$json")
    write_tags "$file" "$s" "$e" || true
  fi
  jq -c --arg how "$how" '. + {source: $how}' <<<"$json"
}

# Prints the first of $1.flac, $1.ogg and $1.mp3 that exists.
find_first_ext() {
  local ext
  for ext in flac ogg mp3; do
    if [[ -f "$1.$ext" ]]; then
      [[ $ext == mp3 ]] && echo "$audio_name: $1.mp3: MP3 loop points may be off by encoder padding; FLAC is recommended" >&2
      printf '%s\n' "$1.$ext"
      return
    fi
  done
}
