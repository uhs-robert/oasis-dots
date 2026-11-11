#!/usr/bin/env bash
# The DesertFox native hosts. They ship only as release assets, so desertfox-host installs them now and `just desertfox-host` updates them.
install_desertfox_host() {
  info "Installing the DesertFox native hosts..."
  bash "$DOTFILES_DIR/lib/install/desertfox-host"
}
