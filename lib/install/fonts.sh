#!/usr/bin/env bash
# Installs the latest MapleMono NF release system-wide (unpinned, needs sudo).
# Download failures only warn: install.sh runs under set -e, and a GitHub rate
# limit or offline machine should not stop the stow step that follows.

_SYSTEM_FONTS_DIR="/usr/local/share/fonts"
_MAPLE_API="https://api.github.com/repos/subframe7536/maple-font/releases/latest"
_MAPLE_BASE="https://github.com/subframe7536/maple-font/releases/download"

_latest_tag() {
  curl -fsSL "$1" | jq -r '.tag_name'
}

_install_maple_mono_nf() {
  local dest="$_SYSTEM_FONTS_DIR/MapleMono-NF"

  if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    warn "MapleMono NF already present, skipping"
    return
  fi

  info "Fetching MapleMono NF release..."
  local version
  version=$(_latest_tag "$_MAPLE_API") || version=""
  if [[ -z "$version" || "$version" == null ]]; then
    warn "Could not fetch MapleMono NF version, skipping"
    return 0
  fi

  local tmp staged
  tmp=$(mktemp -d)
  staged="$tmp/font"
  mkdir -p "$staged"

  local url="$_MAPLE_BASE/${version}/MapleMono-NF.zip"
  if curl -fsSL "$url" -o "$tmp/MapleMono-NF.zip" && unzip -q "$tmp/MapleMono-NF.zip" -d "$staged"; then
    sudo mkdir -p "$_SYSTEM_FONTS_DIR"
    sudo rm -rf "$dest"
    sudo cp -r --no-preserve=ownership "$staged" "$dest"
    sudo fc-cache -f "$_SYSTEM_FONTS_DIR"
    fc-cache -f
    success "MapleMono NF installed system-wide"
  else
    warn "Failed to download or extract MapleMono NF from $url"
  fi

  rm -rf "$tmp"
}

install_fonts() {
  info "Installing custom fonts..."
  require_cmd curl unzip jq

  _install_maple_mono_nf

  success "Fonts installed"
}
