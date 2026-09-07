#!/usr/bin/env bash
# Installs MapleMono NF system-wide.

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
  version=$(_latest_tag "$_MAPLE_API")
  [[ -z "$version" ]] && {
    warn "Could not fetch MapleMono NF version"
    return 1
  }

  local tmp staged
  tmp=$(mktemp -d)
  staged="$tmp/font"
  mkdir -p "$staged"

  local url="$_MAPLE_BASE/${version}/MapleMono-NF.zip"
  if curl -fsSL "$url" -o "$tmp/MapleMono-NF.zip" && unzip -q "$tmp/MapleMono-NF.zip" -d "$staged"; then
    sudo mkdir -p "$_SYSTEM_FONTS_DIR"
    sudo rm -rf "$dest"
    sudo cp -a "$staged" "$dest"
    sudo fc-cache -f "$_SYSTEM_FONTS_DIR"
    fc-cache -f
    success "MapleMono NF installed system-wide"
  else
    warn "Failed to download or extract MapleMono NF from $url"
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$tmp"
}

install_fonts() {
  info "Installing custom fonts..."
  require_cmd curl unzip jq

  _install_maple_mono_nf

  success "Fonts installed"
  warn "Note: 'The Last Shuriken' (used in hyprlock) requires manual installation"
}
