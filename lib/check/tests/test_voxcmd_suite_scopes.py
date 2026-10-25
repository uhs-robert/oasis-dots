"""Tripwire for the per-suite voxcmd scopes in scopes.py: a file under home/voxcmd/tests that a suite reads must reach
that suite, and a fixture must be wired by a rule of its own, not by the home/voxcmd/* fallthrough (which runs every
suite, so a forgotten fixture would never be noticed)."""

import fnmatch
import os
import re
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import keys  # noqa: E402
import scopes  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
TESTS = "home/voxcmd/tests"
FALLTHROUGH = "home/voxcmd/*"

# Each suite's entry scripts. voxcmd-click's run.sh runs the other five beside its own checks.
SUITE_ENTRIES = {
    scopes.VOX_PHRASES: ["run-phrases.sh"],
    scopes.VOX_CLICK: ["run.sh", "run-sessions.sh", "run-modes.sh", "run-sequences.sh", "run-overview.sh", "run-monitors.sh"],
    scopes.VOX_CALENDAR: ["run-calendar.sh"],
    scopes.VOX_WAKE: ["run-wake.sh"],
    scopes.VOX_FIREFOX: ["run-firefox-extension.sh"],
}

EXTENSIONLESS_SCRIPTS = ("firefox-profile", "firefox-fake-host", "firefox-host-test")

# Named in a suite's code but not read by it (a comment-free mention, such as a path in a string it only prints; or a
# same-named file elsewhere: the click suite reads the shipped integrations/click.toml, not the crate's fixture of that
# name).
NOT_READ = {
    (scopes.VOX_CLICK, "click.toml"),
    (scopes.VOX_PHRASES, "bench.sh"),
    (scopes.VOX_PHRASES, "run-live-diff.sh"),
}


def tests_files():
    """Paths relative to the repository root of every file under home/voxcmd/tests, tracked or not."""
    found = []
    for root, _, names in os.walk(os.path.join(REPO, TESTS)):
        if "/target" in root:
            continue
        for name in names:
            found.append(os.path.relpath(os.path.join(root, name), REPO))
    return sorted(found)


def code_of(path):
    """A script's text without its comment lines, which name files they do not read."""
    with open(os.path.join(REPO, path), errors="replace") as handle:
        return "\n".join(line for line in handle if not line.lstrip().startswith("#"))


def mentions(code, path):
    """Whether code names path: by file name for a file with an extension (and the extension-less scripts), by the
    path under tests/ for the rest, whose names (voxcmd, notify-send) are also commands the suites run."""
    name = os.path.basename(path)
    if "." in name or name in EXTENSIONLESS_SCRIPTS:
        needle = name
    else:
        needle = os.path.relpath(path, TESTS)
    return re.search(r"(?<![\w.-])" + re.escape(needle) + r"(?![\w-])", code) is not None


def first_rule(path):
    return next(pattern for pattern, _ in scopes.PATH_SCOPES if fnmatch.fnmatchcase(path, pattern))


class VoxcmdSuiteScopes(unittest.TestCase):
    def test_every_fixture_has_a_rule_of_its_own(self):
        for path in tests_files():
            if not path.startswith(TESTS + "/fixtures/"):
                continue
            with self.subTest(path=path):
                self.assertNotEqual(first_rule(path), FALLTHROUGH, (
                    f"{path} is wired to no suite: add a rule for it in scopes.py naming the suite scopes that read it "
                    "(or \"rust\" when only the crate does), ahead of home/voxcmd/*"))

    def test_a_suite_is_reached_by_every_file_it_reads(self):
        """A file counts as read when its name appears in the suite's code or in the code of a tests/ script that code
        names, so a helper sourced by a suite and the fixtures that helper loads both count."""
        files = tests_files()
        scripts = [path for path in files if "/fixtures/" not in path and path.endswith((".sh", ".py")) or os.path.basename(path) in EXTENSIONLESS_SCRIPTS]
        for suite, entries in SUITE_ENTRIES.items():
            texts = {f"{TESTS}/{name}": code_of(f"{TESTS}/{name}") for name in entries}
            grew = True
            while grew:
                grew = False
                joined = "\n".join(texts.values())
                for path in scripts:
                    if path not in texts and re.search(r"(?<![\w.-])" + re.escape(os.path.basename(path)) + r"\b", joined):
                        texts[path] = code_of(path)
                        grew = True
            joined = "\n".join(texts.values())
            for path in files:
                name = os.path.basename(path)
                if path in texts or (suite, name) in NOT_READ or not mentions(joined, path):
                    continue
                with self.subTest(suite=suite, path=path):
                    self.assertIn(suite, keys.path_scopes(path).split(), (
                        f"{suite} reads {path} but an edit of it does not reach the suite: fix its rule in scopes.py"))
            for path in texts:
                with self.subTest(suite=suite, path=path):
                    self.assertIn(suite, keys.path_scopes(path).split())


if __name__ == "__main__":
    unittest.main()
