#!/bin/sh
# Fails on a voxcmd integration or replacement file that git ignores. All three directories ignore everything not listed in
# their .gitignore, so a new file left off the list never reaches a commit, while the tests in the same checkout still load
# it and pass. Symlinks are skipped: those are private additions linked in from outside the repo on purpose.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
cd "$repo_dir" || exit 1

status=0
for dir in home/voxcmd/.config/voxcmd/integrations home/voxcmd/.config/voxcmd/integrations.d home/voxcmd/.config/voxcmd/replacements.d; do
  for file in $(git ls-files --others --ignored --exclude-standard -- "$dir"); do
    [ -L "$file" ] && continue
    echo "$file is ignored by git, so it would never be committed: add !${file##*/} to $dir/.gitignore" >&2
    status=1
  done
done
exit "$status"
