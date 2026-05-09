#!/usr/bin/env bash
# Installs Nerd Fonts and MapleMono NF to ~/.local/share/fonts.

FONTS_DIR="$HOME/.local/share/fonts"
_NF_API="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
_NF_BASE="https://github.com/ryanoasis/nerd-fonts/releases/download"
_MAPLE_API="https://api.github.com/repos/subframe7536/maple-font/releases/latest"
_MAPLE_BASE="https://github.com/subframe7536/maple-font/releases/download"

_latest_tag() {
  curl -fsSL "$1" | jq -r '.tag_name'
}

_install_nerd_font() {
  local name="$1" version="$2"
  local dest="$FONTS_DIR/$name"
  if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    warn "Font $name already present, skipping"
    return
  fi
  mkdir -p "$dest"
  local url="$_NF_BASE/$version/${name}.tar.xz"
  if ! curl -fsSL "$url" | tar -xJ -C "$dest"; then
    warn "Failed to download $name from $url"
    rm -rf "$dest"
    return 1
  fi
  success "Installed font: $name"
}

_install_maple_mono_nf() {
  local dest="$FONTS_DIR/MapleMono-NF"
  if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    warn "MapleMono NF already present, skipping"
    return
  fi
  info "Fetching MapleMono NF release..."
  local version
  version=$(_latest_tag "$_MAPLE_API")
  [[ -z "$version" ]] && { warn "Could not fetch MapleMono NF version"; return 1; }
  mkdir -p "$dest"
  local tmp
  tmp=$(mktemp -d)
  local url="$_MAPLE_BASE/${version}/MapleMono-NF.zip"
  if curl -fsSL "$url" -o "$tmp/MapleMono-NF.zip"; then
    unzip -q "$tmp/MapleMono-NF.zip" -d "$dest"
    success "MapleMono NF installed"
  else
    warn "Failed to download MapleMono NF from $url"
    rm -rf "$dest"
  fi
  rm -rf "$tmp"
}

install_fonts() {
  info "Installing fonts..."
  require_cmd curl unzip tar
  mkdir -p "$FONTS_DIR"

  info "Fetching Nerd Fonts release..."
  local nf_version
  nf_version=$(_latest_tag "$_NF_API")
  if [[ -z "$nf_version" ]]; then
    warn "Could not fetch Nerd Fonts version, skipping Nerd Fonts"
  else
    info "Nerd Fonts $nf_version"
    while IFS= read -r font; do
      _install_nerd_font "$font" "$nf_version"
    done < <(read_ini_section fonts.ini NERD_FONTS)
  fi

  _install_maple_mono_nf

  fc-cache -f
  success "Fonts installed"

  warn "Note: 'The Last Shuriken' (used in hyprlock) requires manual installation"
}
