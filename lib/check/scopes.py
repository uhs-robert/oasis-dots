"""What lib/check.sh runs and which changes reach each step: tables and a few discovery globs, read by runner.py.

A scope is a folder of the repository (lib/check/README.md lists them), and a change reaches the steps of the scopes its
path falls in. Keep the tables one entry per line. A path that a step in another folder reads gets one entry naming both
scopes, ahead of its folder's rule: a file a step reads but no entry here gives its scope is a file whose edit leaves
a stale pass in place.

Patterns are fnmatch.fnmatchcase globs, where `*` crosses `/` as in a shell `case`: `lib/check/*.py` would also match
lib/check/tests/test_scopes.py, so the modules in the "all" entries below are named one by one.
"""

import fnmatch
import glob
import os
import re

from typing import NamedTuple

# The scopes, one per folder of the repository except the voxcmd ones, which split by how long their tests take. The
# crate and the integrations feed all of the voxcmd scopes, but not voxduck (voxtype's own package).
VOX_PHRASES, VOX_CLICK, VOX_DUCK, VOX_REST, VOX_RUST = "voxphrases", "voxclick", "voxduck", "voxrest", "voxrust"
# runner.py reads this to tell a suite that VOXCMD_ONLY_SECTIONS can cut short from the other steps, so the crate's
# scope VOX_RUST stays out of it.
VOXCMD_SUITE_SCOPES = (VOX_PHRASES, VOX_CLICK, VOX_REST)
VOXCMD_SUITES = " ".join(VOXCMD_SUITE_SCOPES)
VOXCMD_SUITES_AND_CRATE = VOXCMD_SUITES + " " + VOX_RUST

# Every matching entry adds its scope, ahead of the PATH_SCOPES one. Empty since markdown under lib/check maps to no steps.
ADDITIVE_SCOPES = []

# The first matching entry wins, so order matters. Its scopes (space-separated) are what a change to that path reaches;
# "all" reaches every step, and "" only the steps that always run. The final entry sends every path no rule claims to
# "all", so an unforeseen file runs everything.
PATH_SCOPES = [
    # The runner's modules also name checkscope, so check-scope and check-cache are named by their edits.
    ("lib/check.sh", "all"),
    ("lib/check/runner.py", "checkscope all"),
    ("lib/check/scopes.py", "checkscope all"),
    ("lib/check/lock.sh", "checkscope all"),
    ("justfile", "all"),
    (".claude/check-commands", "all"),
    # Markdown runs no step, ahead of every folder rule; the two tables below are generated into .md files that the
    # docs-generated step compares, so those keep it.
    ("docs/keybinds.md", "docsgen"),
    ("home/quickshell/.config/quickshell/README.md", "docsgen"),
    ("*.md", ""),
    # hypr: the Lua config and its tests. The files outside the folder that a step reads come first.
    ("lib/check/steps/lua.sh", "checkscope hypr"),
    (".luacheckrc", "hypr"),
    # The bar's input vectors run the Lua validator and the bar's, so the files either reads reach the quickshell scope.
    ("home/hypr/.config/hypr/config/input/init.lua", "hypr quickshell docsgen"),
    ("home/hypr/.config/hypr/lib/state.lua", "hypr quickshell docsgen"),
    # The greeter monitor generator (install scope) loads the session's JSON reader.
    ("home/hypr/.config/hypr/lib/json.lua", "hypr install quickshell docsgen"),
    # OUTSIDE_REFS in lib/check/steps/qml_paths.py names this file as a consumer of the bar's files.
    ("home/hypr/.config/hypr/scripts/lock-screen.sh", "hypr quickshell docsgen"),
    ("home/hypr/*", "hypr docsgen"),
    (".claude/skills/shadow/shadow.sh", "hypr"),
    ("system/etc/greetd/hyprland.lua", "hypr quickshell install"),
    ("system/etc/greetd/*.lua", "hypr quickshell"),
    ("system/etc/greetd/quickshell/*", "quickshell"),
    ("system/etc/greetd/*", "hypr"),
    ("lib/install/greeter-monitors.lua", "install hypr"),
    # quickshell: the bar, its node and runtime tests, shaders and the lock skins.
    ("lib/common/greeter-files.sh", "quickshell install skills"),
    ("lib/check/steps/qml_ipc.py", "checkscope docsgen"),
    ("lib/check/qml_imports.py", "checkscope quickshell docsgen"),
    ("lib/check/steps/qml_paths.py", "checkscope quickshell docsgen"),
    ("lib/check/qml-ipc.allow", "checkscope"),
    ("lib/check/qml*", "checkscope quickshell"),
    ("lib/check/steps/qml*", "checkscope quickshell"),
    ("lib/check/steps/lock-skins.sh", "checkscope quickshell"),
    ("lib/check/steps/style-exports.sh", "checkscope quickshell"),
    ("lib/check/steps/time-format.sh", "checkscope quickshell"),
    ("lib/check/steps/shaders.sh", "checkscope quickshell"),
    ("home/quickshell/.config/quickshell/scripts/frame-app-corners", "checkscope quickshell"),
    ("home/quickshell/.config/quickshell/*Ipc.qml", "docsgen quickshell"),
    ("home/quickshell/*", "quickshell"),
    # docsgen: the generated tables (keybinds from the keymaps under hypr, IPC from the handlers under quickshell).
    ("lib/check/steps/docs-generated.sh", "checkscope docsgen"),
    ("lib/docs/gen-keybinds", "checkscope docsgen"),
    ("lib/docs/gen-ipc", "checkscope docsgen"),
    ("lib/docs/docgen.py", "checkscope docsgen"),
    # voxcmd. The suites build and run the crate, so its sources reach all of them as well as cargo's own tests (voxrust).
    # Snapshots, the generated goldens and the crate's test sources are read only by cargo test; the other fixtures are
    # read by both. An integration file reaches the suites, and the crate through tests/integrations.rs.
    ("lib/check/steps/voxcmd-rust.sh", "checkscope voxrust"),
    # timer.rs and run-monitors.sh are consumers OUTSIDE_REFS names, so they reach the quickshell scope too.
    ("home/voxcmd/src/timer.rs", VOXCMD_SUITES_AND_CRATE + " quickshell"),
    ("home/voxcmd/tests/run-monitors.sh", VOX_CLICK + " quickshell"),
    ("home/voxcmd/src/*", VOXCMD_SUITES_AND_CRATE),
    ("home/voxcmd/Cargo.*", VOXCMD_SUITES_AND_CRATE),
    ("home/voxcmd/rustfmt.toml", VOX_RUST),
    ("home/voxcmd/tests/*.rs", VOX_RUST),
    ("home/voxcmd/tests/snapshots/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/*-goldens.tsv", VOX_RUST),
    # The shell suites by what each reads (found by following their source/read lines; run.sh stands for voxcmd-click and
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
    ("home/voxcmd/tests/run-calendar.sh", VOX_REST),
    ("home/voxcmd/tests/run-wake.sh", VOX_REST),
    ("home/voxcmd/tests/wake_test.py", VOX_REST),
    ("home/voxcmd/tests/run-firefox-extension.sh", VOX_REST),
    ("home/voxcmd/tests/firefox-host-test", VOX_REST),
    ("home/voxcmd/tests/firefox-background.test.js", VOX_REST),
    # Every suite but the Firefox one runs inside sandbox.sh, whose tests/bin ask-stub they reach the ask stubs through;
    # the Firefox suite shares the voxrest scope, so the scope runs.
    ("home/voxcmd/tests/sandbox.sh", VOXCMD_SUITES),
    ("home/voxcmd/tests/bin/*", VOXCMD_SUITES),
    # Builds the fixture Firefox profile (places.sql, sessionstore.json) for the phrases, click and calendar suites; the
    # calendar one shares voxrest with the Firefox suite, which therefore reruns for no reason.
    ("home/voxcmd/tests/firefox-profile", VOXCMD_SUITES),
    # Run by hand (benchmark, wake sampling), by no step.
    ("home/voxcmd/tests/bench.sh", ""),
    ("home/voxcmd/tests/bench-phrases.tsv", ""),
    ("home/voxcmd/tests/wake-sample.sh", ""),
    # Fixtures: phrase-fixtures.sh loads the desktop's JSON for the phrases suite, window-fixtures.sh a part of it for the
    # click suite; applications/ is the XDG_DATA_HOME both export, and calendar.sh's suite exports it too.
    ("home/voxcmd/tests/fixtures/clients.json", VOX_PHRASES + " " + VOX_CLICK),
    ("home/voxcmd/tests/fixtures/binds.json", VOX_PHRASES + " " + VOX_CLICK),
    ("home/voxcmd/tests/fixtures/applications/*", VOXCMD_SUITES),
    ("home/voxcmd/tests/fixtures/firefox/live-tabs.json", VOX_CLICK),
    ("home/voxcmd/tests/fixtures/firefox/*", VOXCMD_SUITES),
    ("home/voxcmd/tests/fixtures/monitors.json", VOX_PHRASES + " " + VOX_CLICK),
    ("home/voxcmd/tests/fixtures/workspaces.json", VOX_PHRASES),
    ("home/voxcmd/tests/fixtures/pw-dump.json", VOX_PHRASES + " " + VOX_CLICK),
    ("home/voxcmd/tests/fixtures/ocr.tsv", VOX_PHRASES),
    ("home/voxcmd/tests/fixtures/overview.json", VOX_CLICK),
    ("home/voxcmd/tests/fixtures/monitors/*", VOX_CLICK),
    # Only the crate's tests read these (no shell suite names them), except integrations/, which the click suite also reads.
    # A fixture added without a rule here falls to home/voxcmd/*, which test_voxcmd_suite_scopes.py's tripwire rejects.
    ("home/voxcmd/tests/fixtures/monitor-places/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/speech/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/match/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/ask/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/click/*", VOX_RUST),
    ("home/voxcmd/tests/fixtures/integrations/*", VOX_RUST + " " + VOX_CLICK),
    # The suites' own config for these is the sandbox's copy of the package, so a real integration reaches all of them.
    ("home/voxcmd/.config/voxcmd/integrations/*", VOXCMD_SUITES_AND_CRATE),
    # hook_cache.rs and dictation.rs read the shipped share/ files, and the crate's tests read the replacement rules.
    ("home/voxcmd/.local/share/voxcmd/*", VOXCMD_SUITES_AND_CRATE),
    ("home/voxcmd/.config/voxcmd/replacements.d/*", VOXCMD_SUITES_AND_CRATE),
    ("home/voxcmd/*", VOXCMD_SUITES),
    ("home/voxtype/.local/bin/voxtype-daemon", VOXCMD_SUITES),
    # run-wake.sh puts this directory on PATH and asserts the prompt voxcmd builds through it; no other suite runs it.
    ("home/voxtype/.local/bin/voxtype-prompt", VOX_DUCK + " " + VOX_REST),
    ("home/voxtype/*", VOX_DUCK),
    ("home/systemd/.config/systemd/user/voxtype-duck.service", VOX_DUCK),
    ("extras/voxcmd-firefox/*", VOXCMD_SUITES),
    # install: the installer libraries, their tests, the packages they read, and the host-side calendar script.
    ("lib/install/*", "install"),
    ("lib/common/*", "install"),
    ("packages/snapper.ini", "install"),
    ("packages/devtools.ini", "install"),
    ("system/etc/makepkg.conf.d/*", "install"),
    ("system/usr/local/bin/qs-greeter", "install"),
    ("home/calendar/*", "install"),
    # hooks: the agent hooks, the owner-test-bar and orchestrator (reviewers) tests. skills: the ship-batch and merge-prs
    # suites, which take minutes where the hook tests take seconds.
    ("home/claude/.claude/hooks/*", "hooks"),
    ("home/claude/.claude/skills/orchestrator-handoff/*", "hooks"),
    ("home/claude/.claude/skills/orchestrator/*", "hooks"),
    ("home/claude/.claude/skills/merge-prs/*", "skills"),
    (".claude/hooks/*", "hooks"),
    (".claude/skills/owner-test-bar/*", "hooks"),
    (".claude/skills/ship-batch/*", "skills"),
    # checkscope: the runner's own modules and tests, and the scripts whose tests are unittest cases in lib/check/tests.
    ("lib/plan_new.py", "checkscope"),
    ("lib/check/*", "checkscope"),
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


REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def discovered(pattern, scope, command, name_prefix="", always_needs=(), maybe_needs=(), extra_needs=None):
    """One step per file matching pattern (relative to the repository root), named from the file: its stem with `_` as `-`,
    or for a `<dir>/run.sh` pattern the directory's name. Adding a test file that follows the convention needs no entry.
    A step needs always_needs plus those maybe_needs the file's text names, so a test is not skipped for a tool it
    never runs. extra_needs names the tools a test reaches only through a script it sources, by step name."""
    steps = []
    for path in sorted(glob.glob(os.path.join(REPO, pattern))):
        rel = os.path.relpath(path, REPO)
        parts = rel.split("/")
        stem = parts[-2] if parts[-1] == "run.sh" else os.path.splitext(parts[-1])[0]
        with open(path, errors="replace") as handle:
            text = handle.read()
        needs = tuple(always_needs) + tuple(tool for tool in maybe_needs if re.search(r"(?<![\w-])" + tool + r"(?![\w-])", text))
        name = name_prefix + stem.replace("_", "-")
        needs += tuple(tool for tool in (extra_needs or {}).get(name, ()) if tool not in needs)
        skip_reason = f"the {stem} test needs " + ", ".join(needs) if needs else ""
        steps.append(Step(name, scope, command % ("./" + rel), needs, skip_reason=skip_reason))
    return steps


VOXCMD_SKIP = "voxcmd phrases need jq and fzf"
HOOKS_SKIP = "agent hook and owner-test-bar tests need jq"

# Longest first, then the steps found by naming convention (see lib/check/README.md).
STEPS = [
    Step("voxcmd-phrases", VOX_PHRASES, "bash ./home/voxcmd/tests/run-phrases.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-click", VOX_CLICK, "bash ./home/voxcmd/tests/run.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-calendar", VOX_REST, "bash ./home/voxcmd/tests/run-calendar.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-wake", VOX_REST, "bash ./home/voxcmd/tests/run-wake.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxtype-duck", VOX_DUCK, "bash ./home/voxtype/tests/run-duck.sh", ("python3",), skip_reason="the voxtype-duck tests need python3"),
    Step("voxcmd-firefox", VOX_REST, "bash ./home/voxcmd/tests/run-firefox-extension.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-rust", VOX_RUST, "sh ./lib/check/steps/voxcmd-rust.sh", ("cargo",), skip_reason="the voxcmd crate needs cargo"),
    Step("check-scope", "checkscope", "bash ./lib/check/tests/scope.sh"),
    Step("check-cache", "checkscope", "python3 -B -m unittest discover -s lib/check/tests -p 'test_*.py' && bash ./lib/check/tests/lock.sh && bash ./lib/check/tests/shaders.sh"),
    # py_compile would drop a __pycache__ into the stow package, so this parses instead.
    Step("calendar-sync-syntax", "install", "python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' ./home/calendar/.local/bin/calendar-sync"),
    Step("qmllint", "quickshell", "python3 -B ./lib/check/steps/qml.py"),
    Step("shellcheck", "shell", 'status=0; [ ! -s "$CHECK_LOGS/plain.list" ] || xargs shellcheck <"$CHECK_LOGS/plain.list" || status=1; [ ! -s "$CHECK_LOGS/sourcing.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/sourcing.list" || status=1; [ ! -s "$CHECK_LOGS/agent.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/agent.list" || status=1; exit $status', ("shellcheck",), skip_reason="shellcheck not installed"),
    Step("owner-test-bar", "hooks", "bash ./.claude/skills/owner-test-bar/tests/run.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("ship-batch", "skills", "bash ./.claude/skills/ship-batch/tests/run.sh"),
    Step("rebase-branch", "skills", "bash ./.claude/skills/ship-batch/tests/rebase_branch.sh"),
    Step("merge-prs", "skills", "bash ./home/claude/.claude/skills/merge-prs/tests/run.sh"),
    Step("reviewers", "hooks", "bash ./home/claude/.claude/skills/orchestrator/tests/run.sh && bash ./home/claude/.claude/skills/orchestrator/tests/local.sh", ("jq", "git"), skip_reason="the reviewer tests need jq and git"),
    Step("shfmt", "shell", 'status=0; cat "$CHECK_LOGS/plain.fmt.list" "$CHECK_LOGS/sourcing.fmt.list" | grep . | xargs -r shfmt -i 2 -d || status=1; [ ! -s "$CHECK_LOGS/agent.fmt.list" ] || xargs shfmt -i 2 -d <"$CHECK_LOGS/agent.fmt.list" || status=1; exit $status', ("shfmt",), skip_reason="shfmt not installed"),
    Step("stylua", "hypr", "stylua --respect-ignores --check home/hypr/.config/hypr", ("stylua",), skip_reason="stylua not installed"),
    Step("luacheck", "hypr", "sh ./lib/check/steps/lua.sh"),
    Step("qml-paths", "quickshell", "python3 -B ./lib/check/steps/qml_paths.py"),
    Step("qml-layers", "quickshell", "python3 -B ./lib/check/steps/qml_layers.py"),
    Step("qml-singleton-names", "quickshell", "python3 -B ./lib/check/steps/qml_singleton_names.py"),
    Step("qml-ipc", "tree", "python3 -B ./lib/check/steps/qml_ipc.py"),
    Step("readme-links", "tree", "python3 -B ./lib/check/steps/readme_links.py"),
    # "tree" because it reads the Lua keymaps and definitions, lib/check/registry.allow and the Quickshell IpcHandlers: no
    # single scope covers them. No `needs`: a missing lua must fail the step, not skip it.
    Step("registry", "tree", "python3 -B ./lib/check/steps/registry.py"),
    Step("lock-skins", "quickshell", "bash ./lib/check/steps/lock-skins.sh"),
    Step("docs-generated", "docsgen", "sh ./lib/check/steps/docs-generated.sh", ("lua", "python3"), skip_reason="the generated table checks need lua and python3"),
    Step("style-exports", "quickshell", "sh ./lib/check/steps/style-exports.sh"),
    # A probe, not the script's own skip line, so a run without qsb records no pass that would hide a stale .qsb later.
    Step("shaders", "quickshell", "sh ./lib/check/steps/shaders.sh", probe='[ -x "${QSB-}" ] || command -v qsb >/dev/null || [ -x /usr/lib/qt6/bin/qsb ]', skip_reason="the shader check needs qsb (qt6-shadertools)"),
    Step("time-format", "quickshell", "sh ./lib/check/steps/time-format.sh"),
    # The Lua entry points in home/hypr/tests that no .sh wraps (the other .lua files there are helpers of the .sh tests).
    Step("frame-lone-flush", "hypr", "lua ./home/hypr/tests/frame_lone_flush.lua", ("lua",), skip_reason="the hypr tests need lua"),
    Step("bind-action", "hypr", "lua ./home/hypr/tests/bind_action.lua", ("lua",), skip_reason="the hypr tests need lua"),
    Step("act-lib", "hypr", "lua ./home/hypr/tests/act.lua", ("lua",), skip_reason="the hypr tests need lua"),
    Step("theme-state", "hypr", "lua ./home/hypr/tests/theme_state.lua", ("lua",), skip_reason="the hypr tests need lua"),
    Step("submap-hints", "hypr", "lua ./home/hypr/tests/submap_hints.lua", ("lua",), skip_reason="the hypr tests need lua"),
    Step("input-vectors-lua", "quickshell", "lua ./home/quickshell/tests/input_settings/run_lua.lua", ("lua",), skip_reason="the input vectors need lua"),
    Step("input-vectors-js", "quickshell", "node ./home/quickshell/tests/input_settings/run_js.js", ("node",), skip_reason="the input vectors need node"),
    Step("packages", "tree", "sh ./lib/check/steps/packages.sh"),
    Step("symlinks", "tree", "sh ./lib/check/steps/symlinks.sh"),
    Step("git-diff-check", "tree", "git diff --check HEAD"),
    Step("whitespace", "tree", "sh ./lib/check/steps/whitespace.sh"),
    Step("conflicts", "tree", "sh ./lib/check/steps/conflicts.sh"),
    Step("ignored-integrations", "tree", "sh ./lib/check/steps/ignored-integrations.sh"),
]
# Found by naming convention: a new test in one of these places is a step without an entry above.
STEPS += discovered("home/hypr/tests/*.sh", "hypr", "bash %s", maybe_needs=("lua", "jq"), extra_needs={"shadow-action": ("lua", "jq")})
STEPS += discovered("home/quickshell/tests/*.js", "quickshell", "node %s", always_needs=("node",), maybe_needs=("jq",))
STEPS += discovered("home/quickshell/tests/*/run.sh", "quickshell", "bash %s", maybe_needs=("qs", "python3"))
STEPS += discovered("lib/install/tests/*.sh", "install", "bash %s", "install-", maybe_needs=("jq", "zsh"), extra_needs={"install-greeter-stage-zsh": ("jq",)})
STEPS += discovered(".claude/hooks/tests/*.sh", "hooks", "bash %s", "hook-", always_needs=("jq",), maybe_needs=("tmux", "flock"))
STEPS += discovered("home/claude/.claude/hooks/tests/*.sh", "hooks", "bash %s", "hook-", always_needs=("jq",), maybe_needs=("tmux", "flock"))

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
        "home/hypr/.config/hypr/scripts/restart-bar.sh",
        "home/hypr/.local/bin/hypr-act",
        "home/hypr/tests/*.sh",
        "home/voxcmd/tests/*.sh",
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


def path_scopes(path):
    """The scopes a change to path reaches, as a space-separated string: the additive scopes first, then the first
    PATH_SCOPES match's with a leading space."""
    found = " ".join(scope for pattern, scope in ADDITIVE_SCOPES if fnmatch.fnmatchcase(path, pattern))
    for pattern, reached in PATH_SCOPES:
        if fnmatch.fnmatchcase(path, pattern):
            if reached:
                found += " " + reached
            break
    return found
