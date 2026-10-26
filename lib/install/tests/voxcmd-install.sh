#!/usr/bin/env bash
# Tests install_voxcmd against a scratch HOME and a stub cargo: no build, nothing outside the scratch directory.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

export DOTFILES_DIR=$scratch/dotfiles HOME=$scratch/home
unset XDG_DATA_HOME
source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/voice.sh"
mkdir -p "$DOTFILES_DIR" "$HOME/.local/bin" "$scratch/stub"

# Stands in for cargo: `cargo install --root R` leaves an executable R/bin/voxcmd that prints its build hash, or fails.
cat >"$scratch/stub/cargo" <<'STUB'
#!/usr/bin/env bash
[[ -z ${STUB_CARGO_FAIL:-} ]] || exit 1
while (($#)); do [[ $1 == --root ]] && root=$2; shift; done
mkdir -p "$root/bin"
printf '#!/bin/sh\necho "voxcmd %s"\n' "$VOXCMD_GIT_HASH" >"$root/bin/voxcmd"
chmod +x "$root/bin/voxcmd"
STUB
chmod +x "$scratch/stub/cargo"
base_path=$PATH
staged=$HOME/.local/share/voxcmd-rs/bin/voxcmd
failures=0
check() {
  if ! eval "$2"; then
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
  fi
}

# What stow leaves once the bash script is gone, or while it is still there: a link to a repo file.
ln -s "$DOTFILES_DIR/home/voxcmd/.local/bin/voxcmd" "$HOME/.local/bin/voxcmd"

PATH=$scratch/stub:$base_path
STUB_CARGO_FAIL=1 install_voxcmd &>/dev/null && status=0 || status=$?
check "a failed build returns non-zero" "[[ $status != 0 ]]"
check "and leaves stow's link in place" "[[ \$(readlink '$HOME/.local/bin/voxcmd') == '$DOTFILES_DIR/home/voxcmd/.local/bin/voxcmd' ]]"

install_voxcmd &>/dev/null && status=0 || status=$?
check "a build succeeds" "[[ $status == 0 ]]"
check "voxcmd links to the staged binary" "[[ \$(readlink '$HOME/.local/bin/voxcmd') == '$staged' ]]"
check "voxcmd-rs too" "[[ \$(readlink '$HOME/.local/bin/voxcmd-rs') == '$staged' ]]"
check "and it runs through the link" "[[ \$('$HOME/.local/bin/voxcmd') == 'voxcmd unknown' ]]"
install_voxcmd &>/dev/null && status=0 || status=$?
check "a second run is the same" "[[ $status == 0 && \$(readlink '$HOME/.local/bin/voxcmd') == '$staged' ]]"

rm "$HOME/.local/bin/voxcmd"
ln -s "$scratch/gone" "$HOME/.local/bin/voxcmd"
install_voxcmd &>/dev/null
check "a dangling link is replaced" "[[ \$(readlink '$HOME/.local/bin/voxcmd') == '$staged' ]]"

rm "$HOME/.local/bin/voxcmd"
mkdir "$scratch/nocargo"
PATH=$scratch/nocargo:/nonexistent
out=$(install_voxcmd 2>&1) && status=0 || status=$?
PATH=$base_path
[[ $out == *'just voxcmd-build'* ]] && names_recipe=1 || names_recipe=0
check "without cargo it warns and succeeds" "[[ $status == 0 && $names_recipe == 1 ]]"
check "and links nothing" "[[ ! -e '$HOME/.local/bin/voxcmd' && ! -L '$HOME/.local/bin/voxcmd' ]]"

# The binary bakes in the checkout it was built from, which a linked worktree may outlive: skip the build there, like
# `just voxcmd-build` refuses, and leave the install going.
rm -f "$HOME/.local/bin/voxcmd" "$HOME/.local/bin/voxcmd-rs"
git init -q -b main "$scratch/main_repo"
git -C "$scratch/main_repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$scratch/main_repo" worktree add -q "$scratch/linked" -b linked
PATH=$scratch/stub:$base_path
out=$(DOTFILES_DIR=$scratch/linked install_voxcmd 2>&1) && status=0 || status=$?
[[ $out == *'linked worktree'* && $out == *'just voxcmd-build'* ]] && warned=1 || warned=0
check "a linked worktree warns, names the main checkout recipe and succeeds" "[[ $status == 0 && $warned == 1 ]]"
check "and builds and links nothing" "[[ ! -e '$HOME/.local/bin/voxcmd' && ! -L '$HOME/.local/bin/voxcmd' ]]"
out=$(DOTFILES_DIR=$scratch/main_repo install_voxcmd 2>&1) && status=0 || status=$?
check "the main checkout of a git repo still builds" "[[ $status == 0 && -L '$HOME/.local/bin/voxcmd' ]]"
PATH=$base_path

# The swap made the build the only thing that creates the voxcmd link, so a desktop install must call it.
check "install.sh builds voxcmd on a desktop install" "grep -Eq '^ *if \\[\\[ \\\$OPT_SERVER -eq 0 \\]\\]; then install_voxcmd' '$repo_dir/install.sh'"

((failures == 0)) || exit 1
echo "voxcmd-install: ok"
