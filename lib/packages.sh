#!/usr/bin/env bash
# Reads package lists and installs system packages and LuaRocks.

# Strips comments, blanks, and section headers from a plain package list file.
read_pkgs() {
  grep -v '^\s*#\|^\s*$\|^\[' "$PKG_DIR/$1"
}

# Extracts entries under a named [SECTION] from an INI-style package file.
read_ini_section() {
  local file="$1" section="$2"
  awk "/^\[$section\]/{found=1; next} /^\[/{found=0} found && /^[^#[:space:]]/{print}" "$PKG_DIR/$file"
}

# Installs any commands from "$@" that are missing, using the system package manager.
# Command name must match the package name, use install_packages for anything else.
ensure_cmd() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] && return
  info "Bootstrapping missing commands: ${missing[*]}"
  case "$DISTRO" in
  fedora) sudo dnf install -y "${missing[@]}" ;;
  arch)   sudo pacman -S --needed --noconfirm "${missing[@]}" ;;
  esac
}

install_packages() {
  info "Installing system packages..."
  mapfile -t pkgs < <(read_pkgs "$DISTRO.ini")
  case "$DISTRO" in
  fedora) sudo dnf install -y "${pkgs[@]}" ;;
  arch)   sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
  esac
  success "System packages installed"
}

install_pipx_packages() {
  if ! command -v pipx &>/dev/null; then
    warn "pipx not found, skipping"
    return
  fi
  info "Installing pipx packages..."
  while IFS= read -r pkg; do
    pipx install "$pkg" && success "Installed $pkg" || warn "Failed to install $pkg"
  done < <(read_pkgs pipx.ini)
}

install_luarocks_packages() {
  if ! command -v luarocks &>/dev/null; then
    warn "luarocks not found, skipping"
    return
  fi
  info "Installing LuaRocks packages..."
  while IFS= read -r rock; do
    luarocks install --local "$rock"
  done < <(read_pkgs luarocks.ini)
  success "LuaRocks packages installed"
}
