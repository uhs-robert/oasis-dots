#!/bin/sh

# Runs the validation steps and reports all failures, rather than stopping at
# the first one: a single run should show everything that needs fixing.
#
#   lib/check.sh                  every step
#   lib/check.sh --changed <base> only the steps the files changed since <base> can affect
#   lib/check.sh --paths-from <file|-> like --changed, but the changed paths are the lines of the file (or stdin), relative to the
#                                 repository root, instead of `git diff <base>`: a commit's staged paths, say
#   lib/check.sh --only <step>[,<step>...] only the named steps (repeatable), whatever their scope; with --changed or
#                                 --paths-from, those of them the change reaches. An unknown name exits 2 before anything runs
#   lib/check.sh --plan [--changed <base>|--paths-from <file|->] [--only ...] prints the plan (the summary line, then each shellcheck list) and exits 0, running nothing
#
# A step that passes is recorded (lib/check/passed.sh) under a key hashing the content of the files it reads, the same
# files whose change makes --changed pick it (its scope in lib/check/scopes.py); a later run skips a step whose key already passed, uncommitted and
# untracked content included. A run that leaves the tree clean also records the tree: when every step passed for its
# content, or for --changed <base> on top of a base recorded as passed; and a --changed run records that it passed
# against <base>, which is what the PR hook looks up. An --only run records its steps' passes, under the same keys a later
# --changed run looks up, but never the tree or a base. The shell steps (shellcheck, shfmt) key on the run's file lists,
# so for them pass --only the same --changed base the final run will use, or expect it to run them again. With
# VOXCMD_ONLY_SECTIONS set the voxcmd suites run in part, so no run records their pass, the tree or a base.
#
# CHECK_FULL=1 makes --changed run everything, and runs every step whatever passed before. CHECK_JOBS sets how many steps
# run at once (default min(cores/2, 4)); 1 runs them one after another with live output. CHECK_SKIP_STEPS="step ..." drops
# those steps whatever the scope says (the summary line lists them). Everything runs at nice 19 in the idle IO class, and
# the voxcmd suites (not voxcmd-rust) each hold one of CHECK_HEAVY_SLOTS machine-wide slots (lib/check/lock.sh), waiting at most
# CHECK_LOCK_WAIT_SECS (default 1200) for one; CHECK_NO_LOCK=1 runs them without a slot, for a check that must never
# wait (the commit hook).
#
# Where it runs on its own: nothing runs it at the end of a turn, only a commit (.claude/hooks/check-before-commit.sh,
# the committed files), a PR open (.claude/hooks/check-before-pr.sh, which only looks up a recorded pass) and ship-batch
# (each PR's branch, then main). A worktree has no repos/, so its pass does not cover lib/check/steps/symlinks.sh for the main
# checkout: run the check in the real checkout before merging. --changed always runs the cheap steps (git-diff-check,
# whitespace, conflicts, symlinks, packages); a change to this file, the runner's own files under lib/check/, the
# justfile, .claude/check-commands or any path no rule in lib/check/scopes.py claims runs everything. The parallel output of a step is
# buffered and a passing step prints one line; after the FAILED: line, the last 25 lines of each failing step follow. A step
# whose tool is missing prints "skip:" and passes. Run a suite through --only rather than by hand (a hook warns), so its
# pass is recorded and the final --changed run skips it.
#
# Steps (the "needs" tools are optional unless stated; each one's command and scope is in lib/check/scopes.py, where a
# new step goes):
#   lint (shellcheck, shfmt) installer, lib/ (common, install, check), demo/, home/voxcmd/tests/, home/calendar/tests/, the Quickshell audio
#                            importers (scripts/lib/*.sh, ff7-, goldeneye-, mgs2-, ocarina-audio) and the tracked agent scripts
#                            under .claude/ and home/claude/.claude/ (by *.sh name or shell shebang; not worktrees/ or
#                            skills/synced/); shfmt -i 2. Needs shellcheck, shfmt.
#   stylua, luacheck         Hyprland config (stylua) and Hyprland plus greetd Lua (luacheck, via lib/check/steps/lua.sh). Needs
#                            stylua, luacheck or lua5.4/5.3/luajit with LuaFileSystem.
#   qmllint                  Quickshell config and greeter (lib/check/steps/qml.py). Needs Qt 6 qmllint.
#   qml-paths                file paths built as strings in Quickshell QML and JS exist: Qt.resolvedUrl, shellDir, QML and JS
#                            imports, in the shell and in the greeter tree (lib/common/greeter-files.sh), and the files outside
#                            Quickshell that name a path in it (lib/check/steps/qml_paths.py).
#   qml-layers               no Quickshell import or literal URL load runs to a higher layer than its file's, except the edges in
#                            lib/check/qml-layers.allow, which fails when one goes stale (lib/check/steps/qml_layers.py).
#   qml-singleton-names      no Quickshell `pragma Singleton` file is named *Config, *Store or *Manager, except the temporary lines in
#                            lib/check/qml-singleton-names.allow, which fails when one goes stale (lib/check/steps/qml_singleton_names.py).
#   qml-ipc                  every `qs ipc call` target and function in scripts, Lua, Rust, tmux.conf and test stubs is a typed function of an
#                            IpcHandler, and every handler is called, except lib/check/qml-ipc.allow, which fails when a line goes stale
#                            (lib/check/steps/qml_ipc.py). It also checks the README IPC table: a row per handler, and only real functions in a row. Always runs.
#   lock-skins               features/lock/skins/index.json matches the skin files and audio importers (lib/check/steps/lock-skins.sh). Needs jq.
#   style-exports            generated property lines in theme/Style.qml match theme/StyleSchema.js (lib/check/steps/style-exports.sh).
#                            Needs python3.
#   time-format              no hand-built am/pm text in Quickshell QML/JS; clock text goes through TimeFormat
#                            (lib/check/steps/time-format.sh).
#   shaders                  each tracked Quickshell .frag rebuilds (qsb) to its committed .frag.qsb byte for byte, and its `// Rebuild:` header
#                            matches the command used; `just shaders` rewrites them (lib/check/steps/shaders.sh). Needs qsb (qt6-shadertools).
#   voxcmd-phrases           each phrase in home/voxcmd/tests/phrases.tsv routes as recorded (run-phrases.sh). Needs jq, fzf.
#   voxcmd-click             voxcmd's click support (run.sh, with run-sessions.sh, run-sequences.sh, run-overview.sh and run-monitors.sh beside it). Needs jq, fzf.
#   voxcmd-calendar          the calendar phrases against stubs (run-calendar.sh). Needs jq, fzf.
#   voxcmd-wake              the wake word listener (run-wake.sh). Needs jq, fzf.
#   voxcmd-firefox           the Firefox extension and its native-messaging host (run-firefox-extension.sh). Needs jq, fzf;
#                            the extension's script runs under node when present.
#   voxcmd-rust              the voxcmd crate: cargo fmt --check, clippy -D warnings, cargo test (lib/check/steps/voxcmd-rust.sh).
#                            Takes a heavy slot but runs in the pool. Needs cargo.
#   calendar-sync            home/calendar/tests/run.sh. Runs only when python-icalendar and python-recurring-ical-events
#   calendar-sync-syntax     import; the syntax check of calendar-sync always runs.
#   firefox-policy           lib/install/tests/firefox-policy.sh, the Firefox policy installer. Needs jq.
#   greeter-keyring          lib/install/tests/greeter-keyring.sh (the greetd keyring unlock installer) and greeter-log.sh (the greeter log file and the qs-greeter wrapper's choice of it).
#   install-load             lib/install/tests/load.sh, that sourcing the install libraries prints nothing and never exits.
#   agent-hooks              the tests of guard-masked-checks.sh, check-before-pr.sh, restart-qs-after-git.sh, guard-gh-merge.sh
#                            and warn-direct-voxcmd-suite.sh. Needs jq.
#   stale-shells-hook        the test of stale-shells.sh. Needs jq.
#   owner-test-bar           the owner-test-bar skill's tests/run.sh, when it changes. Needs jq.
#   ship-batch, merge-prs    those skills' tests/run.sh, when either changes.
#   notification-markup      home/quickshell/tests/notification_markup.js, the notification body sanitizer. Needs node.
#   check-scope, check-cache which steps --changed picks (lib/check/tests/scope.sh), and the runner's scopes, keys,
#                            pass records and slot lock (lib/check/tests/test_*.py, cache.sh, lock.sh); and shaders.sh, the shaders step's tests.
#   packages                 duplicate package names across the manifests (lib/check/steps/packages.sh).
#   symlinks, whitespace,    tracked symlinks that dangle or leave the repo; trailing whitespace; conflict markers.
#   conflicts, git-diff-check  and `git diff --check HEAD`.
#   ignored-integrations     no voxcmd integration or replacement file is one git ignores (lib/check/steps/ignored-integrations.sh).
#
# Slots and records: only the voxcmd suites hold a CHECK_HEAVY_SLOTS slot, and the voxcmd suites also run one after another
# in a lane of their own (they are timing-sensitive); the cheap steps take none. A step's pass is recorded only when its files did not
# change while it ran. lib/check/passed.sh keeps the records in the repository's common git dir, shared by every worktree.
# On INT or TERM the running steps and their children are ended.
#
# The runner is lib/check/runner.py; this shim works both as `sh lib/check.sh` and `lib/check.sh`.
exec python3 -B "$(dirname -- "$0")/check/runner.py" "$@"
