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

# Reads a whole manifest, or only the sections in "$@" when --server is set.
read_manifest() {
  local file="$1"
  shift
  if [[ "${OPT_SERVER:-0}" -eq 1 ]]; then
    local section
    for section in "$@"; do
      read_ini_section "$file" "$section"
    done
  else
    read_pkgs "$file"
  fi
}

FAILED_PKGS=()

# Installs "$2.." with pacman or paru ($1) in one pass, then per package if that fails.
install_with_retry() {
  local tool="$1" pkg
  shift
  local -a cmd
  case "$tool" in
  pacman) cmd=(sudo pacman -S --needed --noconfirm) ;;
  paru) cmd=(paru -S --needed --noconfirm) ;;
  *) die "install_with_retry: unknown tool '$tool'" ;;
  esac
  [[ $# -gt 0 ]] || return 0
  "${cmd[@]}" "$@" && return 0
  warn "Batch install failed, retrying each package"
  for pkg in "$@"; do
    "${cmd[@]}" "$pkg" || {
      warn "Failed to install $pkg"
      FAILED_PKGS+=("$pkg")
    }
  done
}

print_failed_packages() {
  [[ ${#FAILED_PKGS[@]} -eq 0 ]] && return
  echo ""
  warn "Packages that failed to install: ${FAILED_PKGS[*]}"
}

install_packages() {
  info "Installing system packages..."
  mapfile -t pkgs < <(read_manifest "$DISTRO.ini" CORE SYSTEM CLI DEV)
  install_with_retry pacman "${pkgs[@]}"
  success "System packages processed"
  [[ "${OPT_SERVER:-0}" -eq 1 ]] || check_quickshell_version
}

QS_TESTED_VERSION=0.3.1

# Warns when Quickshell is missing or older than the version this config is tested with.
check_quickshell_version() {
  local have
  have=$(qs --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) || true
  if [[ -z "$have" ]]; then
    warn "Quickshell (qs) not found or its version is unreadable, this config is tested with $QS_TESTED_VERSION"
    return 0
  fi
  if [[ "$(printf '%s\n%s\n' "$QS_TESTED_VERSION" "$have" | sort -V | head -n1)" != "$QS_TESTED_VERSION" ]]; then
    warn "Quickshell $have is older than $QS_TESTED_VERSION, which this config is tested with"
  fi
  return 0
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
      FAILED_PKGS+=("$pkg")
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
    luarocks install --local "$rock" || {
      warn "Failed to install luarock: $rock"
      FAILED_PKGS+=("$rock")
    }
  done < <(read_pkgs luarocks.ini)
  success "LuaRocks packages processed"
}
