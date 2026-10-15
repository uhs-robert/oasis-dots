#!/usr/bin/env bash
# Lets the greetd login unlock the GNOME keyring with the password typed at the greeter, so the first secret lookup after
# login (Slack, calendar-sync) raises no second unlock prompt. PAM can only do that while the keyring's password matches
# the login password; when they differ the keyring stays locked and prompts as before, and the login itself still works.

GREETD_KEYRING_AUTH_LINE='auth       optional     pam_gnome_keyring.so'
GREETD_KEYRING_SESSION_LINE='session    optional     pam_gnome_keyring.so auto_start'

# The paths and the sudo command are overridable so the test can run against scratch files without root.
# GREETD_KEYRING_SUDO may be set to the empty string.
enable_greetd_keyring_unlock() {
  local pam_file="${GREETD_PAM_FILE:-/etc/pam.d/greetd}"
  local module="${PAM_GNOME_KEYRING_MODULE:-/usr/lib/security/pam_gnome_keyring.so}"
  local -a sudo_cmd
  read -ra sudo_cmd <<<"${GREETD_KEYRING_SUDO-sudo}"

  if [[ ! -f "$module" ]]; then
    info "gnome-keyring's PAM module is not installed, skipping the login keyring unlock"
    return 0
  fi
  if [[ ! -f "$pam_file" ]]; then
    warn "$pam_file is missing, so greetd cannot unlock the keyring; install greetd first"
    return 0
  fi

  local add_auth=1 add_session=1
  grep -Eq '^[[:space:]]*-?auth[[:space:]].*pam_gnome_keyring\.so' "$pam_file" && add_auth=0
  grep -Eq '^[[:space:]]*-?session[[:space:]].*pam_gnome_keyring\.so' "$pam_file" && add_session=0
  if ((! add_auth && ! add_session)); then
    info "greetd already unlocks the keyring at login"
    return 0
  fi

  # pacman owns this file, so only our two lines go in, each after the last line of its PAM type; an upgrade then
  # leaves a .pacnew to merge rather than silently losing them.
  local tmp
  tmp=$(mktemp) || return 1
  awk -v add_auth="$add_auth" -v add_session="$add_session" \
    -v auth_line="$GREETD_KEYRING_AUTH_LINE" -v session_line="$GREETD_KEYRING_SESSION_LINE" '
    { lines[NR] = $0; if ($1 == "auth") last_auth = NR; if ($1 == "session") last_session = NR }
    END {
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (add_auth && i == last_auth) print auth_line
        if (add_session && i == last_session) print session_line
      }
      if (add_auth && !last_auth) print auth_line
      if (add_session && !last_session) print session_line
    }' "$pam_file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! "${sudo_cmd[@]}" install -m 644 "$tmp" "$pam_file"; then
    rm -f "$tmp"
    warn "Could not write $pam_file"
    return 1
  fi
  rm -f "$tmp"
  success "greetd now unlocks the keyring at login (needs the keyring password to match your login password)"
}
