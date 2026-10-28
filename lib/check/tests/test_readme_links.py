"""Tests the README link check (lib/check/steps/readme_links.py) on tiny git repositories, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import readme_links  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

README = "qs/README.md"


class LinksCase(TreeCase):
    """A repository with the Quickshell tree in qs/."""

    def check(self, files, ignore=""):
        for name in os.listdir(self.root):
            full = os.path.join(self.root, name)
            shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)
        write_tree(self.root, {".gitignore": ignore, **files})
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return [f"{f.path}:{f.line}: {f.message}" for f in readme_links.run_checks(self.root, "qs")]

    def readme(self, text, **others):
        return self.check({README: text, **others})


class RelativeLinkTest(LinksCase):
    def test_existing_file_and_folder_pass(self):
        self.assertEqual(self.readme("[a](other/A.md) [b](other/) [c](../docs/x.md)\n", **{"qs/other/A.md": "# A\n", "docs/x.md": ""}), [])

    def test_a_dead_link_fails_with_its_line_and_resolved_path(self):
        found = self.readme("fine\n[gone](other/Gone.md)\n")
        self.assertEqual(found, [f"{README}:2: link other/Gone.md points at qs/other/Gone.md, which does not exist"])

    def test_urls_and_images_are_not_followed(self):
        self.assertEqual(self.readme("[w](https://x.org/a) [m](mailto:a@b.c) ![i](missing.png)\n"), [])

    def test_a_link_title_and_angle_brackets_are_read(self):
        self.assertEqual(self.readme('[a](<other/A.md> "title") [b](other/A.md "t")\n', **{"qs/other/A.md": ""}), [])

    def test_links_inside_a_fenced_block_are_prose(self):
        self.assertEqual(self.readme("```\n[x](nowhere.md)\n```\n"), [])

    def test_a_link_in_a_nested_readme_resolves_from_its_own_folder(self):
        files = {"qs/a/README.md": "[up](../b/B.md) [bad](b/B.md)\n", "qs/b/B.md": ""}
        self.assertEqual(self.check(files), ["qs/a/README.md:1: link b/B.md points at qs/a/b/B.md, which does not exist"])


class ReferenceLinkTest(LinksCase):
    def test_defined_references_to_existing_files_and_anchors_pass(self):
        text = "[a][one] [b][] [c]\n\n[one]: other.md#title\n[B]: other.md\n"
        self.assertEqual(self.readme(text, **{"qs/other.md": "# Title\n"}), [])

    def test_a_stale_definition_target_fails_at_the_definition(self):
        found = self.readme("[a][one]\n\n[one]: Gone.md\n")
        self.assertEqual(found, [f"{README}:3: link Gone.md points at qs/Gone.md, which does not exist"])

    def test_a_stale_definition_anchor_fails(self):
        found = self.readme("[a][one]\n[one]: other.md#nope\n", **{"qs/other.md": "# Title\n"})
        self.assertEqual(found, [f"{README}:2: link other.md#nope names no heading of qs/other.md"])

    def test_a_use_without_a_definition_fails(self):
        self.assertEqual(self.readme("see [a][nowhere] and [b][]\n"), [f"{README}:1: reference [b] has no definition", f"{README}:1: reference [nowhere] has no definition"])


class IgnoredTargetTest(LinksCase):
    def test_a_link_to_a_gitignored_missing_file_passes(self):
        self.assertEqual(self.check({README: "[s](custom/sessions.lua)\n[r][x]\n[x]: custom/sessions.lua\n"}, ignore="qs/custom/sessions.lua\n"), [])


class AnchorTest(LinksCase):
    OTHER = "# Title\n\n## Naming singletons\n\n### `Code` and *emph*: more!\n\n## Repeat\n\n## Repeat\n\n```\n## Not a heading\n```\n"

    def check_anchor(self, anchor):
        return self.readme(f"[x](other.md#{anchor})\n", **{"qs/other.md": self.OTHER})

    def test_github_slugs_match(self):
        for anchor in ("title", "naming-singletons", "code-and-emph-more", "repeat", "repeat-1"):
            self.assertEqual(self.check_anchor(anchor), [], anchor)

    def test_a_suffixed_heading_does_not_collide_with_a_later_repeat(self):
        text = "# Foo\n# Foo-1\n# Foo\n"
        for anchor in ("foo", "foo-1", "foo-2"):
            self.assertEqual(self.readme(f"[x](other.md#{anchor})\n", **{"qs/other.md": text}), [], anchor)

    def test_an_unknown_anchor_fails(self):
        self.assertEqual(self.check_anchor("not-a-heading"), [f"{README}:1: link other.md#not-a-heading names no heading of qs/other.md"])

    def test_an_anchor_within_the_same_file(self):
        self.assertEqual(self.readme("# Top\n[a](#top) [b](#nope)\n"), [f"{README}:2: link #nope names no heading of {README}"])

    def test_an_anchor_into_a_non_markdown_file_is_not_checked(self):
        self.assertEqual(self.readme("[a](x.json#anything)\n", **{"qs/x.json": "{}"}), [])


class CitedPathTest(LinksCase):
    def test_paths_resolve_from_the_tree_the_readme_the_root_and_a_stow_package(self):
        files = {
            "qs/features/a/A.qml": "",
            "qs/sub/README.md": "`styles/s/S.js` `features/a/A.qml` `lib/x.sh` `core/`\n",
            "qs/styles/s/S.js": "",
            "qs/core/C.qml": "",
            "lib/x.sh": "",
            "home/system/y": "",
        }
        self.assertEqual(self.check({**files, README: "`system/y`\n"}), [])
        self.assertEqual(self.check({**files, README: "`features/a/A.qml` `home/system/y` `lib/x.sh`\n"}), [])

    def test_a_missing_cited_path_fails(self):
        found = self.readme("one\n`features/a/Gone.qml` and `lib/gone.sh`\n")
        self.assertEqual(len(found), 2)
        self.assertTrue(found[0].startswith(f"{README}:2: `features/a/Gone.qml` does not exist"), found)

    def test_a_missing_folder_with_a_trailing_slash_fails(self):
        self.assertEqual(len(self.readme("`features/gone/`\n")), 1)

    def test_a_gitignored_missing_path_passes(self):
        self.assertEqual(self.check({README: "`custom/mine.lua` `assets/gen/`\n"}, ignore="qs/custom/mine.lua\nqs/assets/gen/\n"), [])

    def test_prose_that_is_not_a_known_folder_path_passes(self):
        text = "`hypr/input.json` `/etc/keyd/x.conf` `$HOME/a/b` `features/*/x` `~/a/b` `a/b c` `<name>/x` `quickshell/style.json`\n"
        self.assertEqual(self.readme(text), [])

    def test_a_path_in_a_link_target_is_not_also_read_as_a_span(self):
        self.assertEqual(self.readme("[`lib/gone.sh`](x.md)\n", **{"qs/x.md": ""}), [f"{README}:1: `lib/gone.sh` does not exist (relative to the Quickshell tree, this file, the repository root or home/)"])

    def test_only_markdown_is_read(self):
        self.assertEqual(self.check({"qs/README.md": "ok\n", "docs/n.txt": "[x](gone.md)\n", "qs/a.txt": "[x](gone.md)\n", "home/k/N.md": "[x](gone.md)\n"}), [])


class DocsTest(LinksCase):
    """docs/ is read like the Quickshell READMEs, backticked paths included."""

    MISSING = "`lib/gone.md`\n"

    def test_a_dead_link_in_docs_fails_with_its_line(self):
        self.assertEqual(self.check({"docs/x.md": "ok\n[gone](nope.md)\n"}), ["docs/x.md:2: link nope.md points at docs/nope.md, which does not exist"])

    def test_a_missing_backticked_path_fails_in_docs(self):
        found = self.check({"docs/x.md": self.MISSING})
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("docs/x.md:1: `lib/gone.md` does not exist"), found)


class RealTreeTest(unittest.TestCase):
    def test_the_quickshell_readmes_have_no_dead_links(self):
        self.assertEqual(readme_links.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
