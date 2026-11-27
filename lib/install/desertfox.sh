#!/usr/bin/env bash
# The DesertFox native hosts. They ship only as release assets, so desertfox-host installs them now and `just desertfox-host` updates them.
install_desertfox_host() {
  info "Installing the DesertFox native hosts..."
  bash "$DOTFILES_DIR/lib/install/desertfox-host"
}

# The same lookup as the desertfox-config recipe in the justfile.
desertfox_checkout() {
  printf '%s\n' "${DESERTFOX_DIR:-$DOTFILES_DIR/repos/desertfox}"
}

# The browser module is wanted when the local DesertFox checkout carries its install script.
desertfox_module_script() {
  local script
  script="$(desertfox_checkout)/browser_module/install.sh"
  [[ -f $script ]] || return 1
  printf '%s\n' "$script"
}

# Needs chrome.d from install_system_files. The script installs the files as root and leaves the enable pref off.
install_desertfox_browser_module() {
  local script
  if ! script=$(desertfox_module_script); then
    info "No DesertFox browser_module/install.sh in $(desertfox_checkout), skipping the browser module"
    return 0
  fi
  info "Installing the DesertFox browser module..."
  sudo bash "$script"
}

uninstall_desertfox_browser_module() {
  local script
  script=$(desertfox_module_script) || return 0
  sudo bash "$script" --uninstall
}
