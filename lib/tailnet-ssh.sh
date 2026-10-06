#!/usr/bin/env bash
# Opt-in SSH server reachable only over Tailscale, so devices on your tailnet (such as a phone running oasis-termux) can reach this machine.

TAILNET_SSHD_CONF=/etc/ssh/sshd_config.d/10-tailnet-only.conf

# sshd keeps the first value it reads for each setting, so an earlier drop-in or Match block can override this one.
# `sshd -t` only checks syntax; this checks what a tailnet connection would actually get.
verify_tailnet_sshd() {
  local effective setting wrong=()
  effective=$(sudo sshd -T -C "user=$USER,host=tailnet-check,addr=100.64.0.1") ||
    die "sshd could not report its effective configuration"
  for setting in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no" "allowusers *@100.64.0.0/10"; do
    grep -qixF "$setting" <<<"$effective" || wrong+=("$setting")
  done
  ((${#wrong[@]} == 0)) && return 0
  die "Another sshd config takes precedence over $TAILNET_SSHD_CONF; the server was not enabled. Expected but missing: ${wrong[*]}. Check /etc/ssh/sshd_config and the other files in /etc/ssh/sshd_config.d/"
}

setup_tailnet_ssh() {
  # An SSH server is never turned on by --yes; it needs an explicit answer.
  if [[ ${OPT_YES:-0} -eq 1 ]]; then
    info "Skipping the SSH server under --yes; run 'just ssh-server' to set it up"
    return 0
  fi
  confirm "Enable an SSH server reachable only over Tailscale (key login only)?" || return 0

  # A full install already has openssh from arch.ini [SYSTEM]; a standalone `just ssh-server` may not.
  [[ -x /usr/bin/sshd ]] || sudo pacman -S --needed --noconfirm openssh
  local packages
  mapfile -t packages < <(read_ini_section ssh-server.ini PACKAGES)
  sudo pacman -S --needed --noconfirm "${packages[@]}"

  grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config ||
    die "/etc/ssh/sshd_config does not include sshd_config.d/*.conf, so $TAILNET_SSHD_CONF would be ignored"

  sudo systemctl enable --now tailscaled
  sudo install -Dm644 "$DOTFILES_DIR/system/etc/ssh/sshd_config.d/10-tailnet-only.conf" "$TAILNET_SSHD_CONF"
  sudo ssh-keygen -A >/dev/null
  sudo sshd -t || die "sshd rejected its configuration; fix it before enabling the server"
  verify_tailnet_sshd
  sudo systemctl enable sshd
  sudo systemctl restart sshd
  success "SSH server enabled: key login only, from Tailscale addresses only"

  local address
  address=$(tailscale ip -4 2>/dev/null | head -n 1)
  if [[ -z $address ]]; then
    warn "Next: sign this machine in to Tailscale with 'sudo tailscale up'"
    address="<this machine's Tailscale address>"
  fi
  info "Allow a device in by adding its public key to ~/.ssh/authorized_keys"
  info "On a phone running oasis-termux, run 'termux-send setup $USER@$address' and paste the line it prints there"
  info "See https://github.com/uhs-robert/oasis-termux#-send-files-to-your-computer"
}
