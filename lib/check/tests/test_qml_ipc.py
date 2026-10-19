"""Tests the IPC caller check (lib/check/steps/qml_ipc.py) on tiny git repositories, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import qml_ipc  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

ALLOW = "allow"
POPUP = """IpcHandler {
    target: "popup"
    function open(name: string): void {}
    function state(): string { return "closed" }
    function helper(x) { return x }
}
"""
OVERVIEW = 'IpcHandler { target: "tmux-overview"; function state(): string { return "" } }\n'


class IpcCase(TreeCase):
    """A repository with the QML in qs/ (and demo/overlay/) and the allowlist in allow."""

    def check(self, files, allow=""):
        for name in os.listdir(self.root):
            full = os.path.join(self.root, name)
            shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)
        write_tree(self.root, {**files, ALLOW: allow})
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        found = qml_ipc.run_checks(self.root, ("qs", "demo/overlay"), ALLOW)
        return [f"{f.path}:{f.line}: {f.message}" for f in found]

    def messages(self, files, allow=""):
        return [line.split(": ", 1)[1] for line in self.check(files, allow)]

    def calls(self, name, text, extra=None):
        """The findings for one caller file beside a popup handler that is called elsewhere."""
        return self.check({"qs/Popup.qml": POPUP, name: text, "bin/keep.sh": "qs-ipc call popup state\n", **(extra or {})})


class DeclaredTest(IpcCase):
    def test_only_typed_functions_count(self):
        self.assertEqual(self.calls("bin/a.sh", "qs-ipc call popup open x\nqs-ipc call popup state\n"), [])
        found = self.messages({"qs/Popup.qml": POPUP, "bin/a.sh": "qs-ipc call popup helper 1\nqs-ipc call popup open\n"})
        self.assertEqual(found, ['target "popup" has no typed function "helper" (has: open, state)'])

    def test_an_untyped_return_or_parameter_is_not_exposed(self):
        qml = 'IpcHandler { target: "t"\n function a(x: int) { }\n function b(x): int { return 1 }\n function c(): void { }\n}\n'
        found = self.messages({"qs/T.qml": qml, "bin/a.sh": "qs-ipc call t a\nqs-ipc call t b\nqs-ipc call t c\n"})
        self.assertEqual([m.split(" (has")[0] for m in found], ['target "t" has no typed function "a"', 'target "t" has no typed function "b"'])

    def test_a_multi_line_signature_and_a_dotted_type_parse(self):
        qml = 'IpcHandler {\n target: "t"\n function pick(\n   kind: string,\n   at: list<int>\n ): string { return "" }\n}\n'
        self.assertEqual(self.check({"qs/T.qml": qml, "bin/a.sh": "qs-ipc call t pick\n"}), [])

    def test_strings_and_comments_hide_functions_and_braces(self):
        qml = 'IpcHandler {\n target: "t"\n // function ghost(): void {\n property string s: "function fake(): string { }"\n function real(): void { }\n}\n'
        found = self.messages({"qs/T.qml": qml, "bin/a.sh": "qs-ipc call t real\nqs-ipc call t ghost\nqs-ipc call t fake\n"})
        self.assertEqual([m.split(" (has")[0] for m in found], ['target "t" has no typed function "ghost"', 'target "t" has no typed function "fake"'])

    def test_nested_functions_do_not_count_and_two_handlers_share_a_file(self):
        qml = 'Item {\n IpcHandler { target: "a"; function x(): void { function inner(): void {} } }\n IpcHandler { target: "b"; function y(): void {} }\n}\n'
        found = self.messages({"qs/T.qml": qml, "bin/a.sh": "qs-ipc call a x\nqs-ipc call b y\nqs-ipc call a inner\n"})
        self.assertEqual([m.split(" (has")[0] for m in found], ['target "a" has no typed function "inner"'])

    def test_a_non_literal_target_fails(self):
        found = self.messages({"qs/T.qml": "IpcHandler { target: root.name }\n"})
        self.assertEqual(found, ["IpcHandler target must be a string literal"])

    def test_a_duplicate_target_fails_naming_both_files(self):
        found = self.messages({"qs/A.qml": POPUP, "qs/B.qml": POPUP, "bin/a.sh": "qs-ipc call popup state\n"})
        self.assertEqual(found, ['IpcHandler target "popup" is also declared at qs/A.qml:1'])

    def test_the_demo_overlay_shares_the_namespace(self):
        demo = 'IpcHandler { target: "demo"; function card(on: bool): void {} }\n'
        self.assertEqual(self.check({"demo/overlay/shell.qml": demo, "bin/a.sh": "qs ipc --pid 1 call demo card\n"}), [])


class CallerSyntaxTest(IpcCase):
    def assert_flagged(self, name, text, target):
        found = self.calls(name, text)
        self.assertEqual(len(found), 1, found)
        self.assertIn(f'target "{target}"', found[0])

    def test_bash_variants(self):
        ok = (
            '"$qs_ipc" call popup open x\n'
            '"${QS_IPC:-$HOME/.config/hypr/scripts/qs-ipc}" call popup state\n'
            "'qs-ipc call popup state'\n"
            'qs ipc --pid "$pid" call popup state\n'
            "$ipc call popup state\n"
        )
        self.assertEqual(self.calls("bin/a.sh", ok), [])
        self.assert_flagged("bin/a.sh", '"${QS_IPC:-x/qs-ipc}" call gone state\n', "gone")
        self.assert_flagged("bin/a.sh", "qs ipc --pid 1 call gone state\n", "gone")

    def test_tmux_conf(self):
        self.assertEqual(self.calls("t/.tmux.conf", "if-shell 'qs-ipc call popup state' 'x'\n"), [])
        self.assert_flagged("t/.tmux.conf", "run-shell 'qs-ipc call gone open'\n", "gone")

    def test_lua_strings_including_a_continuation_line(self):
        ok = 'local c = Scripts.qs_ipc .. " call popup open"\nlocal d = x\n  .. " call popup state >/dev/null"\n'
        self.assertEqual(self.calls("h/a.lua", ok), [])
        self.assert_flagged("h/a.lua", 'run(x .. " call gone open")\n', "gone")
        self.assert_flagged("h/a.lua", 'run(x\n  .. " call gone open")\n', "gone")

    def test_python_argv(self):
        self.assertEqual(self.calls("c/sync", 'run(["qs-ipc", "call", "popup", "state"])\n'), [])
        self.assert_flagged("c/sync", 'run(["qs-ipc", "call", "gone", "state"])\n', "gone")
        self.assertEqual(self.calls("c/sync", 'run(["gdbus", "call", "--session"])\n'), [])

    def test_rust_calls_over_several_lines(self):
        ok = 'qs_ipc_call(&["popup".as_ref(), "open".as_ref(), p.as_os_str()]);\nask(&["popup", "state"], t);\n'
        self.assertEqual(self.calls("s/a.rs", ok), [])
        self.assert_flagged("s/a.rs", 'qs_ipc_call(&[\n    "gone".as_ref(),\n    "open".as_ref(),\n]);\n', "gone")
        found = self.calls("s/a.rs", 'ask(&[\n  "popup",\n  "nope",\n], t);\n')
        self.assertIn('has no typed function "nope"', found[0])
        self.assertIn("s/a.rs:1:", found[0])

    def test_shadow_ipc_and_the_smoke_shorthand(self):
        self.assertEqual(self.calls(".claude/skills/shadow/smoke.sh", "q popup open x\nshadow.sh ipc base popup state\n"), [])
        self.assert_flagged(".claude/skills/shadow/smoke.sh", "q gone open\n", "gone")
        self.assert_flagged("bin/b.sh", "shadow.sh ipc base gone open\n", "gone")
        self.assertEqual(self.calls("bin/b.sh", "q gone open\n"), [])
        self.assertEqual(self.calls("bin/b.sh", "shadow.sh ipc base show\n"), [])

    def test_wrapper_helpers_pinned_to_one_target(self):
        wrapped = 'IpcHandler { target: "screenshot"; function recording_stopped(): void {} }\n'
        path = "home/hypr/.config/hypr/scripts/screenshot.sh"
        extra = {"qs/S.qml": wrapped, "bin/keep2.sh": "qs-ipc call screenshot recording_stopped\n"}
        self.assertEqual(self.calls(path, "qs_call recording_stopped\n", extra), [])
        found = self.calls(path, "qs_call renamed_fn\n", extra)
        self.assertIn('target "screenshot" has no typed function "renamed_fn"', found[0])
        self.assertEqual(self.calls("bin/other.sh", "qs_call renamed_fn\n", extra), [])

    def test_a_for_call_list(self):
        self.assertEqual(self.calls("demo/a.sh", '  for call in "popup state" "popup open"; do\n'), [])
        self.assert_flagged("demo/a.sh", '  for call in "popup state" "gone close"; do\n', "gone")
        self.assertEqual(self.calls("t/a.py", "for call in self.recorded() if x.startswith('a'):\n"), [])

    def test_stub_case_patterns(self):
        self.assertEqual(self.calls("t/sandbox.sh", '  *"call popup state"*) echo ok ;;\n'), [])
        self.assert_flagged("t/sandbox.sh", '  *"call gone state"*) echo ok ;;\n', "gone")

    def test_computed_targets_and_functions_are_skipped(self):
        text = (
            'qs-ipc call "$target" state\n'
            'qs-ipc call $call\n'
            'qs-ipc call "${args[@]}"\n'
            'qs-ipc call popup_$x open\n'
            'qs-ipc call popup "$fn"\n'
            'x .. " call popup " .. name\n'
        )
        self.assertEqual(self.calls("h/a.lua", text), [])

    def test_quoted_literal_words_are_read_and_quoted_interpolations_are_not(self):
        ok = 'qs-ipc call "popup" "open"\nqs-ipc call popup "state"\nqs-ipc call \'popup\' \'state\'\n'
        self.assertEqual(self.calls("bin/a.sh", ok), [])
        self.assert_flagged("bin/a.sh", 'qs-ipc call "gone" "open"\n', "gone")
        found = self.calls("bin/a.sh", 'qs-ipc call popup "nope"\n')
        self.assertIn('has no typed function "nope"', found[0])
        self.assertEqual(self.calls("bin/a.sh", 'qs-ipc call "pop$x" "$fn"\nqs-ipc call popup "o$x"\nqs-ipc call "$t" "gone"\n'), [])

    def test_a_python_argv_must_start_with_qs_ipc(self):
        self.assertEqual(self.calls("c/a.py", 'run(["tool", "call", "api", "get"])\n'), [])
        self.assertEqual(self.calls("c/a.py", 'run(["gdbus", "call", "gone", "x"])\n'), [])
        self.assertEqual(self.calls("c/a.py", 'run([qs_ipc, "call", "popup", "state"])\nrun(["qs", "ipc", "call", "popup", "state"])\n'), [])
        self.assertEqual(self.calls("c/a.py", 'run(["/x/hypr/scripts/qs-ipc", "call", "popup", "state"])\n'), [])
        self.assert_flagged("c/a.py", 'run(["/x/qs-ipc", "call", "gone", "state"])\n', "gone")
        self.assert_flagged("c/a.py", 'run(["qs", "ipc", "call", "gone", "state"])\n', "gone")
        self.assert_flagged("c/a.py", 'run([self.qs_ipc, "call", "gone"])\n', "gone")

    def test_whole_line_comments_are_not_callers_in_each_comment_syntax(self):
        self.assertEqual(self.calls("bin/a.sh", "  # qs-ipc call gone open\n"), [])
        self.assertEqual(self.calls("t/.tmux.conf", "# run-shell 'qs-ipc call gone open'\n"), [])
        self.assertEqual(self.calls("h/a.lua", '-- x .. " call gone open"\n'), [])
        self.assertEqual(self.calls("s/a.rs", '// qs_ipc_call(&["gone", "open"]);\n/// ask(&["gone", "x"])\n'), [])
        self.assertEqual(self.calls("c/a.py", '# run(["qs-ipc", "call", "gone"])\n'), [])
        self.assert_flagged("bin/a.sh", "# note\nqs-ipc call gone open\n", "gone")
        self.assert_flagged("h/a.lua", '# not a lua comment: " call gone open"\n', "gone")
        self.assert_flagged("s/a.rs", '# not a rust comment\nask(&["gone", "x"]);\n', "gone")
        self.assert_flagged("bin/a.sh", "qs-ipc call gone open # trailing comments still count\n", "gone")

    def test_a_caller_after_comment_lines_reports_its_real_line(self):
        found = self.calls("bin/a.sh", "# one\n# a longer second comment line\n\nqs-ipc call gone open\n")
        self.assertEqual([line.split(": ")[0] for line in found if "gone" in line], ["bin/a.sh:4"])

    def test_a_literal_target_with_a_computed_function_still_checks_the_target(self):
        self.assert_flagged("bin/a.sh", 'qs-ipc call gone "$fn"\n', "gone")

    def test_prose_markdown_binaries_and_the_check_itself_are_not_scanned(self):
        extra = {"README.md": "qs-ipc call gone open\n", "lib/check/x.py": '"qs-ipc call gone open"\n', "bin/img": "qs-ipc call gone open\0\n"}
        self.assertEqual(self.calls("bin/a.sh", "# the ipc call failed; <ipc call args>\n", extra), [])


class AllowlistTest(IpcCase):
    FILES = {"qs/Popup.qml": POPUP, "qs/Overview.qml": OVERVIEW}

    def test_an_uncalled_target_needs_a_line_and_passes_with_one(self):
        files = {**self.FILES, "bin/a.sh": "qs-ipc call popup state\n"}
        found = self.messages(files)
        self.assertEqual(len(found), 1)
        self.assertIn('target "tmux-overview" is called by nothing in the repo', found[0])
        self.assertEqual(self.check(files, "uncalled tmux-overview  # nobody yet (permanent)\n"), [])

    def test_an_uncalled_line_goes_stale_when_the_target_is_called(self):
        files = {**self.FILES, "bin/a.sh": "qs-ipc call popup state\nqs-ipc call tmux-overview state\n"}
        found = self.messages(files, "uncalled tmux-overview  # nobody yet (permanent)\n")
        self.assertEqual(found, ["uncalled tmux-overview is stale: something calls it now. Delete the line."])

    def test_an_uncalled_line_goes_stale_when_the_target_is_gone(self):
        files = {"qs/Popup.qml": POPUP, "bin/a.sh": "qs-ipc call popup state\n"}
        found = self.messages(files, "uncalled tmux-overview  # nobody yet (permanent)\n")
        self.assertEqual(found, ["uncalled tmux-overview is stale: no IpcHandler declares it. Delete the line."])

    def test_a_frozen_target_needs_no_caller(self):
        files = {**self.FILES, "bin/a.sh": "qs-ipc call popup state\n"}
        self.assertEqual(self.check(files, "frozen tmux-overview state  # called from elsewhere (permanent)\n"), [])

    def test_a_frozen_function_that_is_missing_or_untyped_fails(self):
        files = {**self.FILES, "bin/a.sh": "qs-ipc call popup state\n"}
        found = self.messages(files, "frozen tmux-overview state close  # called from elsewhere (permanent)\n")
        self.assertEqual(len(found), 1)
        self.assertIn('frozen tmux-overview is stale: it has no typed function "close"', found[0])
        files = {"qs/Popup.qml": POPUP, "bin/a.sh": "qs-ipc call popup state\n"}
        found = self.messages(files, "frozen popup helper  # called from elsewhere (permanent)\n")
        self.assertIn('no typed function "helper"', found[0])

    def test_a_frozen_target_that_is_gone_fails(self):
        files = {"qs/Popup.qml": POPUP, "bin/a.sh": "qs-ipc call popup state\n"}
        found = self.messages(files, "frozen tmux-overview state  # called from elsewhere (permanent)\n")
        self.assertEqual(found, ["frozen tmux-overview is stale: no IpcHandler declares it. Delete the line."])

    def test_malformed_and_duplicate_lines_fail(self):
        files = {"qs/Popup.qml": POPUP, "bin/a.sh": "qs-ipc call popup state\n"}
        allow = "uncalled popup\nfrozen popup  # no function (permanent)\nuncalled x  # why (permanent)\nuncalled x  # why (permanent)\n"
        found = self.messages(files, allow)
        self.assertEqual([m[:9] for m in found if "malformed" in m], ["malformed", "malformed"])
        self.assertIn("duplicate entry for x", found)


class MutationTest(IpcCase):
    """A repository shaped like the real one: a handler, and callers in every kind of file."""

    FILES = {
        "qs/features/TmuxOverviewIpc.qml": 'IpcHandler { target: "tmux-overview"; function state(): string { return "" } }\n',
        "h/lib/actions/menu.lua": 'run(Scripts.qs_ipc .. " call tmux-overview state")\n',
        "t/.tmux.conf": "run-shell 'qs-ipc call tmux-overview state'\n",
        "v/tests/sandbox.sh": '*"call tmux-overview state"*) echo closed ;;\n',
        "v/src/bar.rs": 'ask(&["tmux-overview", "state"], t);\n',
    }

    def test_the_fixture_passes(self):
        self.assertEqual(self.check(self.FILES), [])

    def test_renaming_the_target_in_the_qml_only_flags_every_caller(self):
        files = {**self.FILES, "qs/features/TmuxOverviewIpc.qml": self.FILES["qs/features/TmuxOverviewIpc.qml"].replace("tmux-overview", "tmux_overview")}
        found = self.check(files)
        flagged = sorted(line.split(":")[0] for line in found if "declared by no IpcHandler" in line)
        self.assertEqual(flagged, ["h/lib/actions/menu.lua", "t/.tmux.conf", "v/src/bar.rs", "v/tests/sandbox.sh"])
        self.assertTrue(any('target "tmux_overview" is called by nothing' in line for line in found), found)

    def test_renaming_the_target_in_the_callers_only_fails(self):
        files = {path: text.replace("tmux-overview", "tmux_overview") if not path.endswith(".qml") else text for path, text in self.FILES.items()}
        found = self.check(files)
        self.assertEqual(len(found), 5, found)


class LiveTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(qml_ipc.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
