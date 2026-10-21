#!/usr/bin/env bash
# Optional pacman and makepkg tweaks: colour, parallel downloads, cache cleanup timer and faster, debug-free builds.

PACMAN_CONF=/etc/pacman.conf
MAKEPKG_DROPIN=/etc/makepkg.conf.d/oasis.conf
PACMAN_PARALLEL_DOWNLOADS=10

# Prints $1 with the wanted settings applied inside [options] only; other sections pass through untouched.
# A commented setting is uncommented in place, a missing one is appended at the end of [options],
# and a ParallelDownloads that is already higher is kept.
pacman_conf_tweaked() {
  awk -v want="$PACMAN_PARALLEL_DOWNLOADS" '
    function is_section_header(line) { return line ~ /^[[:space:]]*\[.*\]/ }
    # First pass: which settings are already active in [options]
    NR == FNR {
      if (is_section_header($0)) in_options = ($0 ~ /^[[:space:]]*\[options\]/)
      else if (in_options) {
        if ($0 ~ /^[[:space:]]*Color[[:space:]]*$/) active["Color"] = 1
        if ($0 ~ /^[[:space:]]*ILoveCandy[[:space:]]*$/) active["ILoveCandy"] = 1
        if ($0 ~ /^[[:space:]]*VerbosePkgLists[[:space:]]*$/) active["VerbosePkgLists"] = 1
        if ($0 ~ /^[[:space:]]*ParallelDownloads[[:space:]]*=/) active["ParallelDownloads"] = 1
      }
      next
    }
    # Blank lines wait here so appended settings land before the gap that precedes the next section
    function flush_blanks() { printf "%s", blanks; blanks = "" }
    function append_missing(   key, n, i, order) {
      n = split("Color ILoveCandy VerbosePkgLists ParallelDownloads", order, " ")
      for (i = 1; i <= n; i++) {
        key = order[i]
        if (key in active || key in done) continue
        print (key == "ParallelDownloads") ? "ParallelDownloads = " want : key
      }
    }
    {
      if (is_section_header($0)) {
        if (in_options) { append_missing(); flush_blanks() }
        in_options = ($0 ~ /^[[:space:]]*\[options\]/)
        print; next
      }
      if (!in_options) { print; next }
      if ($0 ~ /^[[:space:]]*$/) { blanks = blanks $0 "\n"; next }
      flush_blanks()
      if ($0 ~ /^#[[:space:]]*(Color|ILoveCandy|VerbosePkgLists)[[:space:]]*$/) {
        key = $0; gsub(/[#[:space:]]/, "", key)
        if (!(key in active) && !(key in done)) { print key; done[key] = 1; next }
      } else if ($0 ~ /^#[[:space:]]*ParallelDownloads[[:space:]]*=/) {
        if (!("ParallelDownloads" in active) && !("ParallelDownloads" in done)) {
          print "ParallelDownloads = " want; done["ParallelDownloads"] = 1; next
        }
      } else if ($0 ~ /^[[:space:]]*ParallelDownloads[[:space:]]*=[[:space:]]*[0-9]+/) {
        value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); sub(/[^0-9].*$/, "", value)
        if (value + 0 < want) { print "ParallelDownloads = " want; next }
      }
      print
    }
    END { if (in_options) { append_missing(); flush_blanks() } }
  ' "$1" "$1"
}

# Rewrites the pacman.conf at $1 only when the tweaked text differs. PACMAN_TWEAKS_SUDO is empty in tests.
apply_pacman_conf_tweaks() {
  local conf=${1:-$PACMAN_CONF} tweaked
  tweaked=$(mktemp) || return 1
  pacman_conf_tweaked "$conf" >"$tweaked" || { rm -f "$tweaked"; return 1; }
  if cmp -s "$conf" "$tweaked"; then
    warn "$conf already tweaked, skipping"
  else
    ${PACMAN_TWEAKS_SUDO-sudo} install -m644 "$tweaked" "$conf"
    success "Updated $conf"
  fi
  rm -f "$tweaked"
}

setup_pacman_tweaks() {
  confirm "Tune pacman and makepkg (colour, parallel downloads, paccache timer, no debug packages)?" || return 0
  info "Tuning pacman and makepkg..."
  apply_pacman_conf_tweaks

  sudo pacman -S --needed --noconfirm pacman-contrib
  sudo install -Dm644 "$DOTFILES_DIR/system/etc/makepkg.conf.d/oasis.conf" "$MAKEPKG_DROPIN"

  if [[ ${OPT_SERVICES:-1} -eq 1 ]]; then
    if systemctl is-enabled paccache.timer &>/dev/null; then
      warn "paccache.timer already enabled, skipping"
    else
      sudo systemctl enable --now paccache.timer
    fi
  fi
  success "pacman and makepkg tuned"
}
