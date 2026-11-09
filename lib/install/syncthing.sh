#!/usr/bin/env bash
# Opt-in Syncthing that syncs each repo's .plans and .logs between two machines, over Tailscale only.
# Config edits go straight into config.xml with the service stopped: a running Syncthing rewrites the file from memory.

SYNCTHING_PORT=22000
SYNCTHING_GUI=127.0.0.1:8384
SYNCTHING_KEEP_VERSIONS=5
# Screenshots and recordings are most of .logs; Syncthing cannot ignore by size, so the list is by extension.
# (?d) lets a host delete a directory that holds only ignored files when the other host deletes it (`plans close` does).
SYNCTHING_LOGS_IGNORES=('(?d)*.png' '(?d)*.jpg' '(?d)*.jpeg' '(?d)*.gif' '(?d)*.webp' '(?d)*.avif' '(?d)*.webm' '(?d)*.mp4' '(?d)*.mkv' '(?d)*.mov')
# The store's temp files (.<name>.<random>.tmp). Conflict copies stay unignored on purpose: they must stay visible.
SYNCTHING_TMP_IGNORE='.*.tmp'

# The order Syncthing itself uses, so the unit (which runs without --home) and this file agree.
syncthing_home() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/syncthing" state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/syncthing"
  if [[ -n ${SYNCTHING_HOME:-} ]]; then
    echo "$SYNCTHING_HOME"
  elif [[ -e $config_dir/config.xml ]]; then
    echo "$config_dir"
  else
    echo "$state_dir"
  fi
}

syncthing_tailscale_ip() { tailscale ip -4 2>/dev/null | head -n 1; }

# Prints "changed" or "unchanged". Args: config.xml, then the mode and its values (see the cases below).
syncthing_edit_config() {
  python3 -I - "$@" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, mode, *args = sys.argv[1:]
tree = ET.parse(path)
root = tree.getroot()
before = ET.tostring(root)


def child(parent, tag):
    found = parent.find(tag)
    if found is None:
        found = ET.SubElement(parent, tag)
    return found


if mode == "tailscale":
    ip = args[0]
    gui = child(root, "gui")
    child(gui, "address").text = args[1]
    options = child(root, "options")
    wanted = f"tcp://{ip}:{args[2]}"
    listening = options.findall("listenAddress")
    if [e.text for e in listening] != [wanted]:
        for stale in listening:
            options.remove(stale)
        ET.SubElement(options, "listenAddress").text = wanted
    for key in ("globalAnnounceEnabled", "localAnnounceEnabled", "relaysEnabled", "natEnabled", "startBrowser"):
        child(options, key).text = "false"
elif mode == "peer":
    device_id, ip, port = args
    device = next((d for d in root.findall("device") if d.get("id") == device_id), None)
    if device is None:
        device = ET.SubElement(root, "device", {"id": device_id, "name": device_id[:7], "compression": "metadata", "introducer": "false"})
    wanted = f"tcp://{ip}:{port}"
    if [e.text for e in device.findall("address")] != [wanted]:
        for address in device.findall("address"):
            device.remove(address)
        ET.SubElement(device, "address").text = wanted
elif mode == "folder":
    folder_id, folder_path, keep = args
    folder = next((f for f in root.findall("folder") if f.get("id") == folder_id), None)
    if folder is None:
        folder = ET.SubElement(root, "folder", {"id": folder_id, "label": folder_id, "path": folder_path, "type": "sendreceive", "fsWatcherEnabled": "true"})
        ET.SubElement(folder, "filesystemType").text = "basic"
    folder.set("path", folder_path)
    shared = {d.get("id") for d in folder.findall("device")}
    for device in root.findall("device"):
        if device.get("id") not in shared:
            ET.SubElement(folder, "device", {"id": device.get("id"), "introducedBy": ""})
    versioning = folder.find("versioning")
    if versioning is None:
        versioning = ET.SubElement(folder, "versioning")
    versioning.set("type", "simple")
    versioning.clear()
    versioning.set("type", "simple")
    ET.SubElement(versioning, "param", {"key": "keep", "val": keep})
    ET.SubElement(versioning, "cleanupIntervalS").text = "3600"
    ET.SubElement(versioning, "fsPath")
    ET.SubElement(versioning, "fsType").text = "basic"
else:
    sys.exit(f"unknown mode {mode}")

if ET.tostring(root) == before:
    print("unchanged")
else:
    ET.indent(tree)
    tree.write(path, encoding="utf-8", xml_declaration=False)
    print("changed")
PY
}

# Adds each wanted line to an ignore file that lacks it. Owner edits stay.
syncthing_write_ignores() {
  local file=$1 line
  shift
  touch "$file"
  for line in "$@"; do
    grep -qxF -- "$line" "$file" || printf '%s\n' "$line" >>"$file"
  done
}

# Runs a command with the unit stopped and starts it again even when the command fails, so a bad edit never leaves
# sync down. Steps inside must end with `|| return`: callers run under set -e, which a function run in an `if` ignores.
syncthing_while_stopped() {
  local status=0
  systemctl --user stop syncthing.service
  "$@" || status=$?
  systemctl --user start syncthing.service || status=$?
  return "$status"
}

syncthing_generate_and_edit() {
  local home=$1 address=$2
  [[ -e $home/config.xml ]] || syncthing generate --home "$home" >/dev/null || return
  syncthing_edit_config "$home/config.xml" tailscale "$address" "$SYNCTHING_GUI" "$SYNCTHING_PORT" >/dev/null || return
  systemctl --user enable syncthing.service
}

setup_syncthing() {
  # Moving private files off this machine is never turned on by --yes; it needs an explicit answer.
  if [[ ${OPT_YES:-0} -eq 1 ]]; then
    info "Skipping Syncthing under --yes; run 'just syncthing' to set it up"
    return 0
  fi
  confirm "Sync each repo's .plans and .logs with another machine over Tailscale (Syncthing)?" || return 0

  local address
  address=$(syncthing_tailscale_ip)
  if [[ -z $address ]]; then
    warn "Tailscale has no address here; sign in with 'sudo tailscale up', then run: just syncthing"
    return 0
  fi

  command -v syncthing >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm syncthing

  # A user unit cannot order itself after the system tailscaled, so it fails at boot until the address exists and retries.
  # The shipped unit allows 4 starts in 60 s, so without StartLimitIntervalSec=0 the retries stop after 40 s.
  local dropin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/syncthing.service.d" dropin
  dropin="$dropin_dir/tailscale-retry.conf"
  local wanted=$'[Unit]\nStartLimitIntervalSec=0\n\n[Service]\nRestart=always\nRestartSec=10'
  if [[ ! -e $dropin || $(<"$dropin") != "$wanted" ]]; then
    mkdir -p "$dropin_dir"
    printf '%s\n' "$wanted" >"$dropin"
    systemctl --user daemon-reload
  fi

  local home
  home=$(syncthing_home)
  mkdir -p "$home"
  # A running Syncthing rewrites config.xml from memory, so stop it first. 2.x generates no default folder.
  syncthing_while_stopped syncthing_generate_and_edit "$home" "$address" || {
    warn "Syncthing setup failed; the service was started again"
    return 1
  }
  success "Syncthing listens on $address:$SYNCTHING_PORT only; no discovery, relays or NAT traversal; the GUI is at $SYNCTHING_GUI"
  info "Next: run 'just syncthing-peer <device-id> <peer-tailscale-ip>' with the other machine's ID, then 'just syncthing-folders'"
}

# The peer is reached at its Tailscale address, since discovery is off.
syncthing_add_peer() {
  local device_id=${1:?device id} peer_ip=${2:?peer Tailscale address} home
  home=$(syncthing_home)
  [[ -e $home/config.xml ]] || die "No Syncthing config at $home; run: just syncthing"
  syncthing_while_stopped syncthing_edit_config "$home/config.xml" peer "$device_id" "$peer_ip" "$SYNCTHING_PORT" >/dev/null ||
    die "Adding the peer failed; the service was started again"
  success "Peer $device_id added at tcp://$peer_ip:$SYNCTHING_PORT"
}

# Two folders per repo so each has its own ignore file and can be paused alone. Repos come from `plans`' own scan.
syncthing_repos() {
  PYTHONPATH="$DOTFILES_DIR/home/plans/.local/lib/plans" python3 -I -c '
import sys
sys.path.insert(0, sys.argv[1])
from plans import roots
print("\n".join(roots.all_repos()))' "$DOTFILES_DIR/home/plans/.local/lib/plans"
}

# Adds both folders for each repo. Takes the repos as arguments.
syncthing_edit_folders() {
  local home=$1 repo name kind dir seen=" "
  shift
  for repo in "$@"; do
    [[ -n $repo ]] || continue
    name=$(basename "$repo")
    if [[ $seen == *" $name "* ]]; then
      warn "Two repos are named $name; only the first gets Syncthing folders"
      continue
    fi
    seen+="$name "
    for kind in plans logs; do
      dir="$repo/.$kind"
      mkdir -p "$dir" || return
      if [[ $kind == logs ]]; then
        syncthing_write_ignores "$dir/.stignore" "$SYNCTHING_TMP_IGNORE" "${SYNCTHING_LOGS_IGNORES[@]}" || return
      else
        syncthing_write_ignores "$dir/.stignore" "$SYNCTHING_TMP_IGNORE" || return
      fi
      syncthing_edit_config "$home/config.xml" folder "$name-$kind" "$dir" "$SYNCTHING_KEEP_VERSIONS" >/dev/null || return
    done
  done
}

syncthing_add_folders() {
  local home
  home=$(syncthing_home)
  [[ -e $home/config.xml ]] || die "No Syncthing config at $home; run: just syncthing"
  local repos
  mapfile -t repos < <(syncthing_repos)
  syncthing_while_stopped syncthing_edit_folders "$home" "${repos[@]}" || die "Adding the folders failed; the service was started again"
  success "Syncthing folders set for ${#repos[@]} repos; share them from the laptop first, in the GUI at $SYNCTHING_GUI"
}
