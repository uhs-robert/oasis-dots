"""What lib/check.sh runs and which changes reach each step: plain tables, read by runner.py and keys.py.

Keep this file data only, one entry per line. A new step goes in STEPS with the scope of the files it reads, and every
path that can affect it gets an entry in PATH_SCOPES naming that scope. A scope decides both when a change reaches a
step and what its pass record covers, so a file a step reads but no entry here gives its scope is a file whose edit
leaves a stale pass in place.

Patterns are fnmatch.fnmatchcase globs, where `*` crosses `/` as in a shell `case`: `lib/check/*.py` would also match
lib/check/tests/test_keys.py, so the modules in the "all" entries below are named one by one.

This file is "all" so that any edit of it selects every step under --changed, but keys.py leaves it out of the "all"
lines of a step's key: a step's key holds its own definition and the scope column of the files it reads, which is
where an edit here that matters to the step shows up.
"""

from typing import NamedTuple

# One scope per bash voxcmd suite, so an edit to a file only one suite reads runs only that suite. VOXCMD_SUITES is for
# what every suite runs (the bash voxcmd itself, its integrations); runner.py reads VOXCMD_SUITE_SCOPES to tell a suite
# from the crate.
VOX_PHRASES, VOX_CLICK, VOX_CALENDAR, VOX_WAKE, VOX_FIREFOX = "voxphrases", "voxclick", "voxcalendar", "voxwake", "voxfirefox"
VOXCMD_SUITE_SCOPES = (VOX_PHRASES, VOX_CLICK, VOX_CALENDAR, VOX_WAKE, VOX_FIREFOX)
VOXCMD_SUITES = " ".join(VOXCMD_SUITE_SCOPES)

# Every matching entry adds its scope, ahead of the PATH_SCOPES one.
ADDITIVE_SCOPES = [
    ("lib/check/*", "checkscope"),
]

# The first matching entry wins, so order matters. Its scopes (space-separated) are what a change to that path reaches;
# "all" reaches every step, and "" only the steps that always run. The final entry sends every path no rule claims to
# "all", so an unforeseen file runs everything.
PATH_SCOPES = [
    ("lib/check.sh", "all"),
    ("lib/check/runner.py", "all"),
    ("lib/check/keys.py", "all"),
    ("lib/check/scopes.py", "all"),
    ("lib/check/lock.sh", "all"),
    ("lib/check/passed.sh", "all"),
    ("lib/check/passed.py", "all"),
    ("justfile", "all"),
    (".claude/check-commands", "all"),
    ("lib/check/steps/lua.sh", "lua"),
    (".luacheckrc", "lua"),
    # The files outside the Quickshell tree that OUTSIDE_REFS in lib/check/steps/qml_paths.py names, ahead of their folders.
    ("home/hypr/.config/hypr/scripts/lock-screen.sh", "lua qml"),
    ("home/voxcmd/.local/bin/voxcmd-alarm", VOXCMD_SUITES + " qml"),
    ("home/voxcmd/tests/run-monitors.sh", VOX_CLICK + " qml"),
    # The input vectors run the Lua validator and the bar's, so the files either reads reach them, ahead of the folders.
    ("home/hypr/.config/hypr/config/input/init.lua", "lua inputvec"),
    ("home/hypr/.config/hypr/lib/state.lua", "lua inputvec"),
    # The greeter monitor generator loads the session's JSON reader.
    ("home/hypr/.config/hypr/lib/json.lua", "lua keyring inputvec"),
    ("home/hypr/*", "lua"),
    # Ahead of the greeter's QML entry.
    ("system/etc/greetd/hyprland.lua", "lua qml keyring"),
    ("system/etc/greetd/*.lua", "lua qml"),
    # ship-batch builds its greeter re-sync regex from the list, and only its suite tests that regex.
    ("lib/common/greeter-files.sh", "qml ship loader keyring"),
    ("lib/check/steps/qml.py", "qml"),
    ("lib/check/qml_imports.py", "qml"),
    ("lib/check/steps/qml_paths.py", "qml"),
    ("lib/check/steps/qml_layers.py", "qml"),
    ("lib/check/qml-layers.allow", "qml"),
    ("lib/check/steps/qml_singleton_names.py", "qml"),
    ("lib/check/qml-singleton-names.allow", "qml"),
    ("lib/check/steps/lock-skins.sh", "qml"),
    ("lib/check/steps/style-exports.sh", "qml"),
    ("lib/check/steps/time-format.sh", "qml"),
    ("lib/check/steps/shaders.sh", "shaders"),
    # Ahead of the Quickshell rule below. Only the shader step reads a .frag; QML names the compiled .qsb by path, which
    # qml-paths checks, so a renamed or deleted .qsb reaches it too.
    # The app-corner generator's tests are unittest cases in lib/check/tests, so the script reaches check-cache.
    ("home/quickshell/.config/quickshell/scripts/frame-app-corners", "checkscope qml"),
    ("home/quickshell/*.frag", "shaders"),
    ("home/quickshell/*.frag.qsb", "shaders qml"),
    ("system/etc/greetd/quickshell/*", "qml"),
    # A runtime test and the one component it pins get their own scope, ahead of the Quickshell rules, so an edit to
    # either runs that test; the files are QML too, so the qml step still reads them.
    ("home/quickshell/tests/input_settings/*", "inputvec qml"),
    ("home/quickshell/.config/quickshell/features/settings/HyprInputValidation.js", "inputvec qml node"),
    ("home/quickshell/.config/quickshell/features/settings/HyprInputSettings.qml", "inputvec qml node"),
    ("home/quickshell/tests/polled_command/*", "polledcmd qml"),
    ("home/quickshell/.config/quickshell/core/PolledCommand.qml", "polledcmd qml node"),
    ("home/quickshell/tests/polled_file/*", "polledfile qml"),
    ("home/quickshell/.config/quickshell/core/PolledFile.qml", "polledfile qml node"),
    ("home/quickshell/tests/restarting_stream/*", "restartstream qml"),
    ("home/quickshell/.config/quickshell/core/RestartingStream.qml", "restartstream qml node"),
    ("home/quickshell/tests/*", "node qml"),
    ("home/quickshell/*", "qml node"),
    ("lib/check/steps/voxcmd-rust.sh", "rust"),
    # Only the Rust step: the voxcmd suites run with VOXCMD_BIN unset, so they exercise the bash voxcmd and never the
    # crate. Snapshots and the generated goldens are read only by cargo test; the other fixtures are read by both. An
    # integration file also reaches the bash voxcmd, and the crate through tests/integrations.rs.
    # VOXCMD_BIN=rs becomes the suites' default at voxcmd 3.2: then src/*, Cargo.*, tests/*.rs, snapshots and goldens
    # must also reach the voxcmd suites; test_rust_edits_skip_bash_suites_until_3_2 fails at that point as a reminder.
    ("home/voxcmd/src/*", "rust"),
    ("home/voxcmd/Cargo.*", "rust"),
    ("home/voxcmd/rustfmt.toml", "rust"),
    ("home/voxcmd/tests/*.rs", "rust"),
    ("home/voxcmd/tests/snapshots/*", "rust"),
    ("home/voxcmd/tests/fixtures/*-goldens.tsv", "rust"),
    ("home/voxcmd/tests/fixtures/legacy-dump.jsonl", "rust"),
    # The bash suites by what each reads (found by following their source/read lines; run.sh stands for voxcmd-click and
    # carries run-sessions, run-modes, run-sequences, run-overview and run-monitors). Ahead of the fixture catch-all below.
    ("home/voxcmd/tests/run-phrases.sh", VOX_PHRASES),
    ("home/voxcmd/tests/phrases.tsv", VOX_PHRASES),
    ("home/voxcmd/tests/phrase-fixtures.sh", VOX_PHRASES),
    ("home/voxcmd/tests/run.sh", VOX_CLICK),
    ("home/voxcmd/tests/run-sessions.sh", VOX_CLICK),
    ("home/voxcmd/tests/run-modes.sh", VOX_CLICK),
    ("home/voxcmd/tests/session-harness.sh", VOX_CLICK),
    ("home/voxcmd/tests/run-sequences.sh", VOX_CLICK),
    ("home/voxcmd/tests/run-overview.sh", VOX_CLICK),
    ("home/voxcmd/tests/lib.sh", VOX_CLICK),
    ("home/voxcmd/tests/window-fixtures.sh", VOX_CLICK),
    ("home/voxcmd/tests/firefox-fake-host", VOX_CLICK),
    ("home/voxcmd/tests/run-calendar.sh", VOX_CALENDAR),
    ("home/voxcmd/tests/run-wake.sh", VOX_WAKE),
    ("home/voxcmd/tests/wake_test.py", VOX_WAKE),
    ("home/voxcmd/tests/run-firefox-extension.sh", VOX_FIREFOX),
    ("home/voxcmd/tests/firefox-host-test", VOX_FIREFOX),
    ("home/voxcmd/tests/firefox-background.test.js", VOX_FIREFOX),
    # Every suite but the Firefox one runs inside sandbox.sh, whose tests/bin shim and ask-stub they reach voxcmd through.
    ("home/voxcmd/tests/sandbox.sh", " ".join([VOX_PHRASES, VOX_CLICK, VOX_CALENDAR, VOX_WAKE])),
    ("home/voxcmd/tests/bin/*", " ".join([VOX_PHRASES, VOX_CLICK, VOX_CALENDAR, VOX_WAKE])),
    # Builds the fixture Firefox profile (places.sql, sessionstore.json) for the phrases, click and calendar suites.
    ("home/voxcmd/tests/firefox-profile", " ".join([VOX_PHRASES, VOX_CLICK, VOX_CALENDAR])),
    # Run by hand (live diff, benchmark, wake sampling), by no step.
    ("home/voxcmd/tests/run-live-diff.sh", ""),
    ("home/voxcmd/tests/bench.sh", ""),
    ("home/voxcmd/tests/bench-phrases.tsv", ""),
    ("home/voxcmd/tests/wake-sample.sh", ""),
    # Fixtures: phrase-fixtures.sh loads the desktop's JSON for the phrases suite, window-fixtures.sh a part of it for the
    # click suite; applications/ is the XDG_DATA_HOME both export, and calendar.sh's suite exports it too.
    ("home/voxcmd/tests/fixtures/clients.json", " ".join([VOX_PHRASES, VOX_CLICK])),
    ("home/voxcmd/tests/fixtures/binds.json", " ".join([VOX_PHRASES, VOX_CLICK])),
    ("home/voxcmd/tests/fixtures/applications/*", " ".join([VOX_PHRASES, VOX_CLICK, VOX_CALENDAR])),
    ("home/voxcmd/tests/fixtures/firefox/live-tabs.json", VOX_CLICK),
    ("home/voxcmd/tests/fixtures/firefox/*", " ".join([VOX_PHRASES, VOX_CLICK, VOX_CALENDAR])),
    ("home/voxcmd/tests/fixtures/monitors.json", VOX_PHRASES),
    ("home/voxcmd/tests/fixtures/workspaces.json", VOX_PHRASES),
    ("home/voxcmd/tests/fixtures/pw-dump.json", " ".join([VOX_PHRASES, VOX_CLICK])),
    ("home/voxcmd/tests/fixtures/ocr.tsv", VOX_PHRASES),
    ("home/voxcmd/tests/fixtures/overview.json", VOX_CLICK),
    ("home/voxcmd/tests/fixtures/monitors/*", VOX_CLICK),
    # Only the crate's tests and the generators of its goldens read these (no bash suite names them). A fixture added
    # without a rule here falls to home/voxcmd/*, which test_voxcmd_suite_scopes.py's tripwire rejects.
    ("home/voxcmd/tests/fixtures/monitor-places/*", "rust"),
    ("home/voxcmd/tests/fixtures/speech/*", "rust"),
    ("home/voxcmd/tests/fixtures/match/*", "rust"),
    ("home/voxcmd/tests/fixtures/ask/*", "rust"),
    ("home/voxcmd/tests/fixtures/click/*", "rust"),
    ("home/voxcmd/tests/fixtures/integrations/*", "rust"),
    ("home/voxcmd/tests/fixtures/gen-*.sh", "rust"),
    # The suites' own config for these is the sandbox's copy of the package, so a real integration reaches all of them.
    ("home/voxcmd/.config/voxcmd/integrations/*", "rust " + VOXCMD_SUITES),
    ("home/voxcmd/*", VOXCMD_SUITES),
    ("home/voxtype/.local/bin/voxtype-daemon", VOXCMD_SUITES),
    # run-wake.sh puts this directory on PATH and asserts the prompt voxcmd builds through it; no other suite runs it.
    ("home/voxtype/.local/bin/voxtype-prompt", "voxtype " + VOX_WAKE),
    ("home/voxtype/*", "voxtype"),
    ("home/systemd/.config/systemd/user/voxtype-duck.service", "voxtype"),
    ("extras/voxcmd-firefox/*", VOXCMD_SUITES),
    # The installer and the justfile call it, but those already run everything.
    ("lib/install/voice.sh", "policy loader"),
    ("lib/install/migrate.sh", "migratelock loader"),
    ("lib/install/tests/migrate-lock-assets.sh", "migratelock"),
    ("lib/install/tests/migrate-quickshell-state.sh", "migratelock"),
    ("lib/install/tests/migrate-quickshell-input.sh", "migratelock"),
    ("lib/install/tests/migrate-quickshell-weather.sh", "migratelock"),
    ("lib/install/tests/firefox-policy.sh", "policy"),
    ("lib/install/pacman.sh", "pacman loader"),
    ("lib/install/tests/pacman-tweaks.sh", "pacman"),
    ("system/etc/makepkg.conf.d/*", "pacman"),
    ("lib/install/greeter.sh", "keyring loader"),
    ("lib/install/tests/greeter-keyring.sh", "keyring"),
    ("lib/install/tests/greeter-log.sh", "keyring"),
    ("lib/install/tests/greeter-monitors.sh", "keyring"),
    ("lib/install/tests/greeter-stage-zsh.sh", "keyring"),
    ("lib/install/greeter-monitors.lua", "keyring lua"),
    ("system/usr/local/bin/qs-greeter", "keyring"),
    # Every install library is sourced by the loader test, as are the common ones it loads.
    ("lib/install/*.sh", "loader"),
    ("lib/common/*.sh", "loader"),
    ("home/calendar/*", "calendar"),
    ("home/claude/.claude/hooks/*", "hooks"),
    ("home/claude/.claude/skills/orchestrator-handoff/*", "hooks"),
    (".claude/hooks/live-hypr.sh", "hooks ship"),
    (".claude/hooks/*", "hooks"),
    (".claude/skills/owner-test-bar/*", "bar"),
    (".claude/skills/ship-batch/*", "ship"),
    ("home/claude/.claude/skills/merge-prs/*", "ship"),
    ("system/etc/greetd/*", "lua"),
    # Only the steps that always run (whitespace, conflicts, symlinks, packages, git diff) look at these, plus the
    # shell linters for the shell files among them.
    ("lib/*", ""),
    ("install.sh", ""),
    ("uninstall.sh", ""),
    ("demo/*", ""),
    ("packages/*", ""),
    ("docs/*", ""),
    ("extras/*", ""),
    ("system/*", ""),
    ("home/*", ""),
    (".claude/*", ""),
    ("*.md", ""),
    ("LICENSE", ""),
    ("*", "all"),
]


class Step(NamedTuple):
    name: str
    # Which files the step reads (see PATH_SCOPES). Two scopes are special: "tree" steps scan the whole checkout and
    # always run; "shell" steps read the SHELL_GROUPS lists.
    scope: str
    # Run by sh in the repository root, with CHECK_LOGS (the run's temp dir, holding the shell lists) and CHECK_JOBS set.
    command: str
    # Commands that must be on PATH, else the step prints "skip: <skip_reason>" and counts as passing.
    needs: tuple = ()
    # A shell command that must succeed, else the same skip.
    probe: str = ""
    skip_reason: str = ""
    # Run one after another in a lane of their own, ahead of the rest: they are timing-sensitive.
    serial_lane: bool = False


VOXCMD_SKIP = "voxcmd phrases need jq and fzf"
HOOKS_SKIP = "agent hook and owner-test-bar tests need jq"

# Every step, longest first.
STEPS = [
    Step("voxcmd-phrases", VOX_PHRASES, "bash ./home/voxcmd/tests/run-phrases.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-click", VOX_CLICK, "bash ./home/voxcmd/tests/run.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-calendar", VOX_CALENDAR, "bash ./home/voxcmd/tests/run-calendar.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-wake", VOX_WAKE, "bash ./home/voxcmd/tests/run-wake.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxtype-duck", "voxtype", "bash ./home/voxtype/tests/run-duck.sh", ("python3",), skip_reason="the voxtype-duck tests need python3"),
    Step("voxcmd-firefox", VOX_FIREFOX, "bash ./home/voxcmd/tests/run-firefox-extension.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-rust", "rust", "sh ./lib/check/steps/voxcmd-rust.sh", ("cargo",), skip_reason="the voxcmd crate needs cargo"),
    Step("check-scope", "checkscope", "bash ./lib/check/tests/scope.sh"),
    Step("check-cache", "checkscope", "python3 -B -m unittest discover -s lib/check/tests -p 'test_*.py' && bash ./lib/check/tests/cache.sh && bash ./lib/check/tests/lock.sh && bash ./lib/check/tests/shaders.sh"),
    Step("firefox-policy", "policy", "bash ./lib/install/tests/firefox-policy.sh", ("jq",), skip_reason="the firefox policy test needs jq"),
    Step("pacman-tweaks", "pacman", "bash ./lib/install/tests/pacman-tweaks.sh"),
    Step("greeter-keyring", "keyring", "bash ./lib/install/tests/greeter-keyring.sh && bash ./lib/install/tests/greeter-log.sh && bash ./lib/install/tests/greeter-monitors.sh"),
    Step("greeter-stage-zsh", "keyring", "bash ./lib/install/tests/greeter-stage-zsh.sh", ("zsh", "jq"), skip_reason="the greeter zsh staging test needs zsh and jq"),
    Step("migrate-lock", "migratelock", "bash ./lib/install/tests/migrate-lock-assets.sh && bash ./lib/install/tests/migrate-quickshell-state.sh && bash ./lib/install/tests/migrate-quickshell-input.sh && bash ./lib/install/tests/migrate-quickshell-weather.sh"),
    Step("install-load", "loader", "bash ./lib/install/tests/load.sh"),
    Step("qmllint", "qml", "python3 -B ./lib/check/steps/qml.py"),
    Step("shellcheck", "shell", 'status=0; [ ! -s "$CHECK_LOGS/plain.list" ] || xargs shellcheck <"$CHECK_LOGS/plain.list" || status=1; [ ! -s "$CHECK_LOGS/sourcing.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/sourcing.list" || status=1; [ ! -s "$CHECK_LOGS/agent.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/agent.list" || status=1; exit $status', ("shellcheck",), skip_reason="shellcheck not installed"),
    Step("calendar-sync", "calendar", "bash ./home/calendar/tests/run.sh", probe="python3 -c 'import icalendar, recurring_ical_events' >/dev/null 2>&1", skip_reason="calendar-sync tests need python-icalendar and python-recurring-ical-events"),
    Step("owner-test-bar", "bar", "bash ./.claude/skills/owner-test-bar/tests/run.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("ship-batch", "ship", "bash ./.claude/skills/ship-batch/tests/run.sh"),
    Step("merge-prs", "ship", "bash ./home/claude/.claude/skills/merge-prs/tests/run.sh"),
    Step("shfmt", "shell", 'status=0; cat "$CHECK_LOGS/plain.fmt.list" "$CHECK_LOGS/sourcing.fmt.list" | grep . | xargs -r shfmt -i 2 -d || status=1; [ ! -s "$CHECK_LOGS/agent.fmt.list" ] || xargs shfmt -i 2 -d <"$CHECK_LOGS/agent.fmt.list" || status=1; exit $status', ("shfmt",), skip_reason="shfmt not installed"),
    Step("stylua", "lua", "stylua --respect-ignores --check home/hypr/.config/hypr", ("stylua",), skip_reason="stylua not installed"),
    Step("luacheck", "lua", "sh ./lib/check/steps/lua.sh"),
    Step("qml-paths", "qml", "python3 -B ./lib/check/steps/qml_paths.py"),
    Step("qml-layers", "qml", "python3 -B ./lib/check/steps/qml_layers.py"),
    Step("qml-singleton-names", "qml", "python3 -B ./lib/check/steps/qml_singleton_names.py"),
    Step("qml-ipc", "tree", "python3 -B ./lib/check/steps/qml_ipc.py"),
    Step("readme-links", "tree", "python3 -B ./lib/check/steps/readme_links.py"),
    Step("lock-skins", "qml", "bash ./lib/check/steps/lock-skins.sh"),
    Step("style-exports", "qml", "sh ./lib/check/steps/style-exports.sh"),
    # A probe, not the script's own skip line, so a run without qsb records no pass that would hide a stale .qsb later.
    Step("shaders", "shaders", "sh ./lib/check/steps/shaders.sh", probe='[ -x "${QSB-}" ] || command -v qsb >/dev/null || [ -x /usr/lib/qt6/bin/qsb ]', skip_reason="the shader check needs qsb (qt6-shadertools)"),
    Step("time-format", "qml", "sh ./lib/check/steps/time-format.sh"),
    # py_compile would drop a __pycache__ into the stow package, so this parses instead.
    Step("calendar-sync-syntax", "calendar", "python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' ./home/calendar/.local/bin/calendar-sync"),
    Step("agent-hooks", "hooks", "bash ./home/claude/.claude/hooks/tests/guard-masked-checks.sh && bash ./.claude/hooks/tests/check-before-pr.sh && bash ./.claude/hooks/tests/restart-qs-after-git.sh && bash ./.claude/hooks/tests/guard-gh-merge.sh && bash ./.claude/hooks/tests/warn-direct-voxcmd-suite.sh && bash ./home/claude/.claude/hooks/tests/guard-tmux-socket.sh && bash ./.claude/hooks/tests/guard-check-full.sh && bash ./home/claude/.claude/hooks/tests/context-budget.sh && bash ./home/claude/.claude/hooks/tests/remind-global-neutral.sh && bash ./.claude/hooks/tests/remind-global-neutral-source.sh && bash ./home/claude/.claude/hooks/tests/orchestrator-window-names.sh && bash ./.claude/hooks/tests/report-failed-main-check.sh", ("jq", "tmux", "flock"), skip_reason=HOOKS_SKIP),
    Step("stale-shells-hook", "hooks", "bash ./home/claude/.claude/hooks/tests/stale-shells.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("json-store", "qml", "bash ./home/quickshell/tests/json_store/run.sh", ("qs", "python3"), skip_reason="the json-store tests need qs and python3"),
    Step("polled-command", "polledcmd", "bash ./home/quickshell/tests/polled_command/run.sh", ("qs", "python3"), skip_reason="the polled-command tests need qs and python3"),
    Step("polled-file", "polledfile", "bash ./home/quickshell/tests/polled_file/run.sh", ("qs", "python3"), skip_reason="the polled-file tests need qs and python3"),
    Step("restarting-stream", "restartstream", "bash ./home/quickshell/tests/restarting_stream/run.sh", ("qs", "python3"), skip_reason="the restarting-stream tests need qs and python3"),
    Step("frame-lone-flush", "lua", "lua ./home/hypr/tests/frame_lone_flush.lua", ("lua",), skip_reason="the frame tests need lua"),
    Step("input-vectors-lua", "inputvec", "lua ./home/quickshell/tests/input_settings/run_lua.lua", ("lua",), skip_reason="the input vectors need lua"),
    Step("input-vectors-js", "inputvec", "node ./home/quickshell/tests/input_settings/run_js.js", ("node",), skip_reason="the input vectors need node"),
    Step("notification-markup", "node", "node ./home/quickshell/tests/notification_markup.js", ("node",), skip_reason="notification markup tests need node"),
    Step("toast-extent", "node", "node ./home/quickshell/tests/toast_extent.js", ("node",), skip_reason="the toast extent tests need node"),
    Step("bar-layout", "node", "node ./home/quickshell/tests/bar_layout.js", ("node",), skip_reason="the bar layout tests need node"),
    Step("island-shapes", "node", "node ./home/quickshell/tests/island_shapes.js", ("node",), skip_reason="the island shape tests need node"),
    Step("drawer-shapes", "node", "node ./home/quickshell/tests/drawer_shapes.js", ("node",), skip_reason="the drawer shape tests need node"),
    Step("packages", "tree", "sh ./lib/check/steps/packages.sh"),
    Step("symlinks", "tree", "sh ./lib/check/steps/symlinks.sh"),
    Step("git-diff-check", "tree", "git diff --check HEAD"),
    Step("whitespace", "tree", "sh ./lib/check/steps/whitespace.sh"),
    Step("conflicts", "tree", "sh ./lib/check/steps/conflicts.sh"),
    Step("ignored-integrations", "tree", "sh ./lib/check/steps/ignored-integrations.sh"),
]

# The shell files by the group shellcheck lints them in, as shell globs (one left unmatched stays in the list as
# written). A group is linted whole when any member changes, since a member can source another.
SHELL_GROUPS = {
    "plain": [
        "install.sh",
        "uninstall.sh",
        "lib/check.sh",
        "lib/common/*.sh",
        "lib/install/*.sh",
        "lib/install/tests/*.sh",
        "demo/*.sh",
        "home/hypr/.config/hypr/scripts/state-write",
        "home/voxcmd/tests/*.sh",
        "home/calendar/tests/*.sh",
        "lib/check/*.sh",
        "lib/check/steps/*.sh",
        "lib/check/tests/*.sh",
    ],
    # Linted with -x, which follows `source`, so each is checked together with its libraries.
    "sourcing": [
        "home/quickshell/.config/quickshell/scripts/lib/*.sh",
        "home/quickshell/.config/quickshell/scripts/ff7-audio",
        "home/quickshell/.config/quickshell/scripts/goldeneye-audio",
        "home/quickshell/.config/quickshell/scripts/mgs2-audio",
        "home/quickshell/.config/quickshell/scripts/ocarina-audio",
    ],
}

# The "agent" group: tracked *.sh files plus extension-less files whose first line matches AGENT_SHEBANG, under these
# roots. Symlinks are skipped (their target is linted itself). worktrees/ holds other agents' scratch copies and
# skills/synced/ is vendored.
AGENT_SHELL_ROOTS = [".claude", "home/claude/.claude"]
AGENT_SHELL_EXCLUDES = [".claude/worktrees", "home/claude/.claude/skills/synced"]
AGENT_SHEBANG = r"^#!.*[/ ](ba|da|z)?sh( |$)"
