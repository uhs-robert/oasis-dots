"""What lib/check.sh runs and which changes reach each step: plain tables, read by runner.py and keys.py.

Keep this file data only, one entry per line. A new step goes in STEPS with the scope of the files it reads, and every
path that can affect it gets an entry in PATH_SCOPES naming that scope. A scope decides both when a change reaches a
step and what its pass record covers, so a file a step reads but no entry here gives its scope is a file whose edit
leaves a stale pass in place.

Patterns are fnmatch.fnmatchcase globs, where `*` crosses `/` as in a shell `case`: `lib/check/*.py` would also match
lib/check/tests/test_keys.py, so the modules in the "all" entries below are named one by one.
"""

from typing import NamedTuple

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
    ("home/hypr/*", "lua"),
    # Ahead of the greeter's QML entry.
    ("system/etc/greetd/*.lua", "lua qml"),
    # ship-batch builds its greeter re-sync regex from the list, and only its suite tests that regex.
    ("lib/common/greeter-files.sh", "qml ship loader"),
    ("lib/check/steps/qml.sh", "qml"),
    ("lib/check/steps/lock-skins.sh", "qml"),
    ("lib/check/steps/style-exports.sh", "qml"),
    ("lib/check/steps/time-format.sh", "qml"),
    ("system/etc/greetd/quickshell/*", "qml"),
    ("home/quickshell/tests/*", "node"),
    ("home/quickshell/*", "qml node"),
    ("home/voxcmd/*", "voxcmd"),
    ("extras/voxcmd-firefox/*", "voxcmd"),
    # The installer and the justfile call it, but those already run everything.
    ("lib/install/voice.sh", "policy loader"),
    ("lib/install/tests/firefox-policy.sh", "policy"),
    ("lib/install/greeter.sh", "keyring loader"),
    ("lib/install/tests/greeter-keyring.sh", "keyring"),
    # Every install library is sourced by the loader test, as are the common ones it loads.
    ("lib/install/*.sh", "loader"),
    ("lib/common/*.sh", "loader"),
    ("home/calendar/*", "calendar"),
    ("home/claude/.claude/hooks/*", "hooks"),
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
    Step("voxcmd-phrases", "voxcmd", "bash ./home/voxcmd/tests/run-phrases.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-click", "voxcmd", "bash ./home/voxcmd/tests/run.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-calendar", "voxcmd", "bash ./home/voxcmd/tests/run-calendar.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-wake", "voxcmd", "bash ./home/voxcmd/tests/run-wake.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("voxcmd-firefox", "voxcmd", "bash ./home/voxcmd/tests/run-firefox-extension.sh", ("jq", "fzf"), skip_reason=VOXCMD_SKIP, serial_lane=True),
    Step("check-scope", "checkscope", "bash ./lib/check/tests/scope.sh"),
    Step("check-cache", "checkscope", "python3 -B -m unittest discover -s lib/check/tests -p 'test_*.py' && bash ./lib/check/tests/cache.sh && bash ./lib/check/tests/lock.sh"),
    Step("firefox-policy", "policy", "bash ./lib/install/tests/firefox-policy.sh", ("jq",), skip_reason="the firefox policy test needs jq"),
    Step("greeter-keyring", "keyring", "bash ./lib/install/tests/greeter-keyring.sh"),
    Step("install-load", "loader", "bash ./lib/install/tests/load.sh"),
    Step("qmllint", "qml", "bash ./lib/check/steps/qml.sh"),
    Step("shellcheck", "shell", 'status=0; [ ! -s "$CHECK_LOGS/plain.list" ] || xargs shellcheck <"$CHECK_LOGS/plain.list" || status=1; [ ! -s "$CHECK_LOGS/sourcing.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/sourcing.list" || status=1; [ ! -s "$CHECK_LOGS/agent.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$CHECK_LOGS/agent.list" || status=1; exit $status', ("shellcheck",), skip_reason="shellcheck not installed"),
    Step("calendar-sync", "calendar", "bash ./home/calendar/tests/run.sh", probe="python3 -c 'import icalendar, recurring_ical_events' >/dev/null 2>&1", skip_reason="calendar-sync tests need python-icalendar and python-recurring-ical-events"),
    Step("owner-test-bar", "bar", "bash ./.claude/skills/owner-test-bar/tests/run.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("ship-batch", "ship", "bash ./.claude/skills/ship-batch/tests/run.sh"),
    Step("merge-prs", "ship", "bash ./home/claude/.claude/skills/merge-prs/tests/run.sh"),
    Step("shfmt", "shell", 'status=0; cat "$CHECK_LOGS/plain.fmt.list" "$CHECK_LOGS/sourcing.fmt.list" | grep . | xargs -r shfmt -i 2 -d || status=1; [ ! -s "$CHECK_LOGS/agent.fmt.list" ] || xargs shfmt -i 2 -d <"$CHECK_LOGS/agent.fmt.list" || status=1; exit $status', ("shfmt",), skip_reason="shfmt not installed"),
    Step("stylua", "lua", "stylua --respect-ignores --check home/hypr/.config/hypr", ("stylua",), skip_reason="stylua not installed"),
    Step("luacheck", "lua", "sh ./lib/check/steps/lua.sh"),
    Step("lock-skins", "qml", "bash ./lib/check/steps/lock-skins.sh"),
    Step("style-exports", "qml", "sh ./lib/check/steps/style-exports.sh"),
    Step("time-format", "qml", "sh ./lib/check/steps/time-format.sh"),
    # py_compile would drop a __pycache__ into the stow package, so this parses instead.
    Step("calendar-sync-syntax", "calendar", "python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' ./home/calendar/.local/bin/calendar-sync"),
    Step("agent-hooks", "hooks", "bash ./home/claude/.claude/hooks/tests/guard-masked-checks.sh && bash ./.claude/hooks/tests/check-before-pr.sh && bash ./.claude/hooks/tests/restart-qs-after-git.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("stale-shells-hook", "hooks", "bash ./home/claude/.claude/hooks/tests/stale-shells.sh", ("jq",), skip_reason=HOOKS_SKIP),
    Step("notification-markup", "node", "node ./home/quickshell/tests/notification_markup.js", ("node",), skip_reason="notification markup tests need node"),
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
