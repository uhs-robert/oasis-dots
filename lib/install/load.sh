#!/usr/bin/env bash
# Loads every install library. Callers set DOTFILES_DIR first, then call require_arch if they need $DISTRO.
# Sourcing prints nothing and never exits, so every file under install/ must only define at source time.
[[ -n ${_INSTALL_LOADED:-} ]] && return 0
_INSTALL_LOADED=1
: "${DOTFILES_DIR:?load.sh needs DOTFILES_DIR}"

# The common files depend on each other (distro.sh uses output.sh), so their order is explicit.
# shellcheck source=lib/common/output.sh
source "$DOTFILES_DIR/lib/common/output.sh"
# shellcheck source=lib/common/distro.sh
source "$DOTFILES_DIR/lib/common/distro.sh"
# shellcheck source=lib/common/packages.sh
source "$DOTFILES_DIR/lib/common/packages.sh"

for _install_lib in "$DOTFILES_DIR"/lib/install/*.sh; do
  [[ $_install_lib == */load.sh ]] && continue
  # shellcheck source=/dev/null
  source "$_install_lib"
done
unset _install_lib
