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
  sudo pacman -S --needed --noconfirm "${missing[@]}"
}

install_packages() {
  info "Installing system packages..."
  mapfile -t pkgs < <(read_pkgs "$DISTRO.ini")
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  success "System packages installed"
}

install_pipx_packages() {
  if ! command -v pipx &>/dev/null; then
    warn "pipx not found, skipping"
    return
  fi
  info "Installing pipx packages..."
  while IFS= read -r pkg; do
    if pipx install "$pkg"; then
      success "Installed $pkg"
    else
      warn "Failed to install $pkg"
    fi
  done < <(read_pkgs pipx.ini)
}

print_manual_installs() {
  local file="$PKG_DIR/$DISTRO.ini"
  [[ -f "$file" ]] || return
  local notes
  notes=$(awk '/^\[MANUAL\]/{found=1; next} /^\[/{found=0} found && /^#/{print}' "$file")
  [[ -z "$notes" ]] || {
    echo ""
    warn "Manual installs required:"
    echo "$notes"
  }
}

install_luarocks_packages() {
  if ! command -v luarocks &>/dev/null; then
    warn "luarocks not found, skipping"
    return
  fi
  info "Installing LuaRocks packages..."
  while IFS= read -r rock; do
    luarocks install --local "$rock" || warn "Failed to install luarock: $rock"
  done < <(read_pkgs luarocks.ini)
  success "LuaRocks packages installed"
}
