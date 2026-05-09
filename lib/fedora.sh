#!/usr/bin/env bash
# Fedora-specific setup: enables COPR repos before package installation.

enable_coprs() {
  [[ "$DISTRO" != fedora ]] && return
  info "Enabling Fedora COPR repos..."

  while IFS= read -r repo; do
    sudo dnf copr enable -y "$repo" && success "Enabled $repo" || warn "Failed to enable $repo"
  done < <(read_ini_section fedora-copr.ini CORE)

  if confirm "Enable gaming COPR repos (xone, xpadneo)?"; then
    while IFS= read -r repo; do
      sudo dnf copr enable -y "$repo" && success "Enabled $repo" || warn "Failed to enable $repo"
    done < <(read_ini_section fedora-copr.ini GAMING)
  fi

  info "Optional COPR repos (Tab to select, Enter to confirm):"
  mapfile -t optional_coprs < <(
    read_ini_section fedora-copr.ini OPTIONAL | fzf --multi --prompt="coprs> " --no-info
  )
  for repo in "${optional_coprs[@]}"; do
    sudo dnf copr enable -y "$repo" && success "Enabled $repo" || warn "Failed to enable $repo"
  done
}
