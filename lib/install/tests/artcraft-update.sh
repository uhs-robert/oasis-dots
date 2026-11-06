#!/usr/bin/env bash
# Tests lib/install/artcraft-update offline: curl, pacman and sudo are stubs, and a throwaway key signs a fake release.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
script="$repo_dir/lib/install/artcraft-update"
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

failures=0
expect() { # case_name, output, wanted substring
  [[ $2 == *"$3"* ]] || {
    printf 'FAIL %s: wanted "%s", got: %s\n' "$1" "$3" "$2" >&2
    failures=$((failures + 1))
  }
}
reject() { # case_name, output, unwanted substring
  [[ $2 != *"$3"* ]] || {
    printf 'FAIL %s: did not want "%s", got: %s\n' "$1" "$3" "$2" >&2
    failures=$((failures + 1))
  }
}

case $(uname -m) in
x86_64 | aarch64) arch=$(uname -m) ;;
*)
  echo "skip: no ArtCraft package for $(uname -m)"
  exit 0
  ;;
esac

# The fake release: storytold/<app>/releases/download/v<version>/... under $scratch/web.
mkdir -m 700 "$scratch/signer"
gpg --homedir "$scratch/signer" --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-gen-key "Test Release <t@t>" ed25519 sign never 2>/dev/null
fingerprint=$(gpg --homedir "$scratch/signer" --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
release() { # app, version
  local dir="$scratch/web/$1/releases/download/v$2" file="$1-$2-linux-$arch.pkg.tar.zst"
  mkdir -p "$dir"
  echo "$1 $2" >"$dir/$file"
  (cd "$dir" && sha256sum "$file" >SHA256SUMS.txt)
  gpg --homedir "$scratch/signer" --batch --quiet --armor --detach-sign -o "$dir/SHA256SUMS.txt.asc" "$dir/SHA256SUMS.txt" 2>/dev/null
  gpg --homedir "$scratch/signer" --batch --armor --export >"$dir/release-signing-key.asc"
  echo "$2" >"$scratch/web/$1/latest"
}

# curl: "-w %{url_effective} .../releases/latest" prints the tag URL, "-o <file> <url>" copies from $scratch/web.
mkdir "$scratch/bin"
cat >"$scratch/bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" url="" want_url=0
while (($#)); do
  case $1 in
    -o) out=$2; shift ;;
    -w) want_url=1; shift ;;
    --max-time) shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done
path=${url#https://github.com/storytold/}
if ((want_url)); then
  app=${path%%/*}
  [[ -f $WEB/$app/latest ]] || exit 22
  printf 'https://github.com/storytold/%s/releases/tag/v%s' "$app" "$(cat "$WEB/$app/latest")"
  exit 0
fi
[[ -f $WEB/$path ]] || exit 22
cp "$WEB/$path" "$out"
EOF
# pacman: -Q answers from $INSTALLED ("name version" lines), -U records its arguments.
cat >"$scratch/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case $1 in
  -Q) grep "^$2 " "$INSTALLED" || exit 1 ;;
  -U) shift; printf 'pacman -U %s\n' "$*" ;;
esac
EOF
chmod +x "$scratch/bin/curl" "$scratch/bin/pacman"
: >"$scratch/installed"
export PATH="$scratch/bin:$PATH" WEB="$scratch/web" INSTALLED="$scratch/installed" ARTCRAFT_SUDO="" ARTCRAFT_FINGERPRINT="$fingerprint"
printf 'photocraft\n# a comment\n\nvectorcraft\n' >"$scratch/artcraft.ini"
export ARTCRAFT_MANIFEST="$scratch/artcraft.ini"

release photocraft 0.20.2
release vectorcraft 0.21.1
echo "ai.storyteller.photocraft 0.15.1-1" >"$scratch/installed"
echo "ai.storyteller.vectorcraft 0.21.1-1" >>"$scratch/installed"

out=$(bash "$script" 2>&1)
expect "behind app updates" "$out" "photocraft 0.15.1 -> 0.20.2"
expect "behind app reaches pacman" "$out" "photocraft-0.20.2-linux-$arch.pkg.tar.zst"
reject "current app is left alone" "$out" "vectorcraft"

out=$(bash "$script" --check 2>&1)
expect "check lists the behind app" "$out" "photocraft 0.15.1 -> 0.20.2"
reject "check never installs" "$out" "pacman -U"

: >"$scratch/installed"
out=$(bash "$script" vectorcraft 2>&1)
expect "named app installs when missing" "$out" "vectorcraft not installed -> 0.21.1"
reject "a named app limits the run" "$out" "photocraft"

out=$(ARTCRAFT_FINGERPRINT=0000000000000000000000000000000000000000 bash "$script" photocraft 2>&1)
status=$?
expect "a key other than the pinned one is refused" "$out" "failed its signature or checksum"
reject "a refused package never reaches pacman" "$out" "pacman -U"
((status != 0)) || {
  echo "FAIL a refused package exits nonzero" >&2
  failures=$((failures + 1))
}

echo "tampered" >>"$scratch/web/photocraft/releases/download/v0.20.2/photocraft-0.20.2-linux-$arch.pkg.tar.zst"
out=$(bash "$script" photocraft 2>&1)
expect "a changed package fails its checksum" "$out" "failed its signature or checksum"

out=$(bash "$script" missingcraft 2>&1)
expect "an unknown app is reported" "$out" "missingcraft: could not read the latest release"

((failures == 0)) && echo "artcraft-update: all passed"
exit $((failures > 0))
