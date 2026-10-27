#!/usr/bin/env bash
# Optional btrfs snapshots of / with snapper and snap-pac: the root config and its limits, the timers, and btrfs quotas off.

# The tests point these at a scratch tree and set SNAPPER_SUDO empty.
SNAPPER_CONFIG=${SNAPPER_CONFIG:-root}
SNAPPER_SUBVOLUME=${SNAPPER_SUBVOLUME:-/}
SNAPPER_CONFIG_DIR=${SNAPPER_CONFIG_DIR:-/etc/snapper/configs}
SNAPPER_TIMERS=(snapper-timeline.timer snapper-cleanup.timer)

# Hourly snapshots plus snap-pac's pre/post pair around each pacman transaction, pruned by count.
# QGROUP stays empty because btrfs quotas stay off: with them on, deleting a snapshot recounts every shared
# extent inside the transaction commit, and anything that syncs a file waits minutes for it.
wanted_snapper_settings() {
  printf '%s\n' \
    "ALLOW_USERS=$USER" SYNC_ACL=yes QGROUP= \
    NUMBER_CLEANUP=yes NUMBER_MIN_AGE=1800 NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10 \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_MIN_AGE=1800 \
    TIMELINE_LIMIT_HOURLY=10 TIMELINE_LIMIT_DAILY=10 TIMELINE_LIMIT_WEEKLY=0 \
    TIMELINE_LIMIT_MONTHLY=2 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=5 \
    EMPTY_PRE_POST_CLEANUP=yes EMPTY_PRE_POST_MIN_AGE=1800
}

# Prints the wanted_snapper_settings lines whose value differs in the config text $1 (KEY="value" lines).
snapper_settings_to_change() {
  local config_text=$1 setting key wanted current
  while IFS= read -r setting; do
    key=${setting%%=*} wanted=${setting#*=}
    current=$(sed -n "s/^${key}=\"\(.*\)\"\$/\1/p" <<<"$config_text")
    [[ $current == "$wanted" ]] || printf '%s\n' "$setting"
  done < <(wanted_snapper_settings)
}

snapshots_path() { echo "${SNAPPER_SUBVOLUME%/}/.snapshots"; }

# snapper create-config always makes .snapshots a subvolume nested inside the one it snapshots, and refuses when
# .snapshots exists. When it is already a mount of its own subvolume (archinstall's layout), that mount is lifted
# for create-config, the nested subvolume swapped for an empty mountpoint, and the mount put back.
create_snapper_config() {
  local sudo=${SNAPPER_SUDO-sudo} snapshots_dir snapshots_device snapshots_subvol
  snapshots_dir=$(snapshots_path)
  if ${sudo} test -f "$SNAPPER_CONFIG_DIR/$SNAPPER_CONFIG"; then
    warn "snapper config '$SNAPPER_CONFIG' already exists, keeping it"
    return 0
  fi
  if ! mountpoint -q "$snapshots_dir"; then
    ${sudo} snapper -c "$SNAPPER_CONFIG" create-config "$SNAPPER_SUBVOLUME"
    return
  fi

  snapshots_device=$(findmnt -vno SOURCE "$snapshots_dir") && snapshots_subvol=$(findmnt -no FSROOT "$snapshots_dir") || return 1
  ${sudo} umount "$snapshots_dir" || return 1
  # rmdir, not rm -r: it refuses a directory that still holds snapshots, whatever state the unmount left.
  if ! ${sudo} rmdir "$snapshots_dir"; then
    ${sudo} mount -o "subvol=$snapshots_subvol" "$snapshots_device" "$snapshots_dir"
    return 1
  fi
  local config_created=0
  ${sudo} snapper -c "$SNAPPER_CONFIG" create-config "$SNAPPER_SUBVOLUME" && config_created=1
  if [[ $config_created -eq 1 ]]; then
    ${sudo} btrfs subvolume delete "$snapshots_dir" >/dev/null || return 1
  fi
  # The mount goes back even when create-config failed, so a failed run leaves the layout as it found it.
  ${sudo} mkdir "$snapshots_dir" && ${sudo} mount -o "subvol=$snapshots_subvol" "$snapshots_device" "$snapshots_dir" || return 1
  [[ $config_created -eq 1 ]]
}

apply_snapper_settings() {
  local sudo=${SNAPPER_SUDO-sudo} config_text changes
  config_text=$(${sudo} cat "$SNAPPER_CONFIG_DIR/$SNAPPER_CONFIG") || return 1
  mapfile -t changes < <(snapper_settings_to_change "$config_text")
  if [[ ${#changes[@]} -eq 0 ]]; then
    warn "snapper settings already applied, skipping"
    return 0
  fi
  ${sudo} snapper -c "$SNAPPER_CONFIG" set-config "${changes[@]}" && success "snapper settings applied"
}

disable_btrfs_quotas() {
  local sudo=${SNAPPER_SUDO-sudo}
  # qgroup show fails only when quotas are off.
  if ! ${sudo} btrfs qgroup show "$SNAPPER_SUBVOLUME" &>/dev/null; then
    warn "btrfs quotas already off, skipping"
    return 0
  fi
  ${sudo} btrfs quota disable "$SNAPPER_SUBVOLUME" && success "btrfs quotas turned off"
}

enable_snapper_timers() {
  local sudo=${SNAPPER_SUDO-sudo} timer disabled_timers=()
  # One is-enabled per timer: given several units it succeeds when any one is enabled.
  for timer in "${SNAPPER_TIMERS[@]}"; do
    systemctl is-enabled "$timer" &>/dev/null || disabled_timers+=("$timer")
  done
  if [[ ${#disabled_timers[@]} -eq 0 ]]; then
    warn "snapper timers already enabled, skipping"
    return 0
  fi
  ${sudo} systemctl enable --now "${disabled_timers[@]}" && success "snapper timers enabled"
}

setup_snapper() {
  if [[ $(findmnt -no FSTYPE "$SNAPPER_SUBVOLUME") != btrfs ]]; then
    warn "$SNAPPER_SUBVOLUME is not btrfs, skipping snapper"
    return 0
  fi
  confirm "Snapshot / with snapper (hourly, and before and after each pacman transaction)?" || return 0
  info "Setting up snapper..."
  local snapper_packages
  mapfile -t snapper_packages < <(read_pkgs snapper.ini)
  ${SNAPPER_SUDO-sudo} pacman -S --needed --noconfirm "${snapper_packages[@]}" || return 1
  create_snapper_config || {
    warn "snapper config '$SNAPPER_CONFIG' was not created; fix the error above, then run: just snapper"
    return 1
  }
  apply_snapper_settings && disable_btrfs_quotas && enable_snapper_timers && success "snapper set up"
}
