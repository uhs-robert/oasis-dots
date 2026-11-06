#!/usr/bin/env bash
# The ArtCraft apps. They ship only as release packages, so artcraft-update installs them now and topgrade updates them.
install_artcraft() {
  confirm "Install the ArtCraft apps in packages/artcraft.ini (photo, vector, office, audio and video)?" || return 0
  bash "$DOTFILES_DIR/lib/install/artcraft-update"
}
