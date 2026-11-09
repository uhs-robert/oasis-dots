"""ls filters and order, waiting, questions, and the ask/blocked/work lines of next."""

import os
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import parse, query, validate  # noqa: E402


def make(doc_id, rank, status="planned", owner="none", waiting_on='""', depends_on="[]", project="proj", questions=""):
    head = (f"id: {doc_id}\nproject: {project}\nkind: feature\nstatus: {status}\nowner_session: {owner}\nrank: {rank}\n"
            f"depends_on: {depends_on}\nwaiting_on: {waiting_on}\n")
    body = f"# {doc_id}\n\n## Open questions\n\n{questions}\n## Owner checks\n"
    return parse.Doc(f"/r/.plans/{project}/{doc_id}.md", f"---\n{head}---\n{body}")


def ids(docs):
    return [doc.id for doc in docs]


def lines(steps):
    return [(step.action, step.doc.id, step.detail) for step in steps]


class ConflictCopyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = self.temp.name
        self.dir = os.path.join(self.root, ".plans", "proj")
        os.makedirs(self.dir)
        for name in ("a.md", "a.sync-conflict-20261109-101500-ABCDEFG.md", ".stignore", ".stfolder.md", "note.txt"):
            with open(os.path.join(self.dir, name), "w", encoding="utf-8") as handle:
                handle.write("x\n")
        for name in (".stfolder", ".stversions"):
            os.makedirs(os.path.join(self.root, ".plans", name))
            with open(os.path.join(self.root, ".plans", name, "a.md"), "w", encoding="utf-8") as handle:
                handle.write("x\n")

    def tearDown(self):
        self.temp.cleanup()

    def test_doc_paths_skips_the_copy_and_dot_entries(self):
        self.assertEqual([os.path.basename(path) for path in query.doc_paths(self.root)], ["a.md"])

    def test_conflict_paths_lists_only_copies(self):
        copies = query.conflict_paths(self.root)
        self.assertEqual([os.path.basename(path) for path in copies], ["a.sync-conflict-20261109-101500-ABCDEFG.md"])
        self.assertEqual(query.conflict_original(copies[0]), "a.md")

    def test_find_does_not_see_the_copy(self):
        self.assertEqual(len(query.find(self.root, "a")), 1)


class ListingTest(unittest.TestCase):
    def test_rank_order_and_filters(self):
        docs = [make("c", 30, owner="s-1"), make("a", 10, status="done"), make("b", 20, project="other"), make("x", '"high"')]
        self.assertEqual(ids(query.listing(docs)), ["a", "b", "c", "x"])
        self.assertEqual(ids(query.listing(docs, owner="s-1")), ["c"])
        self.assertEqual(ids(query.listing(docs, project="other")), ["b"])
        self.assertEqual(ids(query.listing(docs, status="done,planned")), ["a", "b", "c", "x"])
        self.assertEqual(ids(query.listing(docs, status="done")), ["a"])

    def test_waiting(self):
        docs = [make("a", 10), make("b", 20, waiting_on='"owner: colour"')]
        self.assertEqual(ids(query.waiting(docs)), ["b"])

    def test_questions(self):
        docs = [make("a", 10, questions="- [ ] First?\n- [x] Answered\n- [ ] Second?\n"), make("b", 5)]
        self.assertEqual([(q.doc.id, q.text) for q in query.questions(docs)], [("a", "First?"), ("a", "Second?")])


class ReadRepoTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = temp.name
        for doc_id, rank in (("good-a", 10), ("good-b", 30)):
            self.write(doc_id, make(doc_id, rank).text.encode())

    def write(self, doc_id, data):
        path = os.path.join(self.root, ".plans", "proj", doc_id + ".md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(data)
        return path

    def check_one_unreadable(self, doc_id, cause):
        repo = query.read_repo(self.root)
        self.assertEqual(ids(repo.docs), ["good-a", "good-b"])
        self.assertEqual(ids(repo.unreadable), [doc_id])
        bad = repo.unreadable[0]
        self.assertEqual(len(bad.errors), 1)
        self.assertIn(cause, bad.errors[0][1])

    def test_a_doc_that_is_not_utf8_is_unreadable_and_the_rest_read(self):
        self.write("bad", b"---\nid: bad\n---\n\xff\xfe\n")
        self.check_one_unreadable("bad", "not UTF-8")

    @unittest.skipIf(os.geteuid() == 0, "root reads a mode 000 file")
    def test_a_doc_with_mode_000_is_unreadable_and_the_rest_read(self):
        path = self.write("locked", make("locked", 20).text.encode())
        os.chmod(path, 0)
        self.check_one_unreadable("locked", "Permission denied")

    def test_a_dangling_symlink_is_unreadable_and_the_rest_read(self):
        path = os.path.join(self.root, ".plans", "proj", "dangling.md")
        os.symlink(os.path.join(self.root, "missing.md"), path)
        repo = query.read_repo(self.root)
        self.assertEqual(ids(repo.docs), ["good-a", "good-b"])
        self.assertEqual(ids(repo.unreadable), ["dangling"])

    def test_a_doc_that_vanishes_mid_read_still_raises(self):
        self.write("gone", make("gone", 20).text.encode())
        real_read = parse.read

        def read(path):
            if path.endswith("gone.md"):
                os.unlink(path)
            return real_read(path)

        with mock.patch.object(parse, "read", read):
            with self.assertRaises(FileNotFoundError):
                query.read_repo(self.root)

    def test_a_permission_error_is_unreadable_under_a_mock(self):
        """Covers the permission case where the file system or the user ignores mode 000."""
        self.write("locked", make("locked", 20).text.encode())
        real_read = parse.read

        def read(path):
            if path.endswith("locked.md"):
                raise PermissionError(13, "Permission denied", path)
            return real_read(path)

        with mock.patch.object(parse, "read", read):
            self.check_one_unreadable("locked", "Permission denied")


class NextTest(unittest.TestCase):
    def test_first_free_doc_is_work(self):
        docs = [make("b", 20), make("a", 10, status="building"), make("idea", 5, status="idea")]
        self.assertEqual(lines(query.next_steps(docs)), [("work", "a", "building")])

    def test_asks_above_the_work_line(self):
        docs = [
            make("ask1", 10, waiting_on='"owner: which colour"'),
            make("dep", 20, depends_on="[ask1]"),
            make("free", 30),
            make("ask-below", 40, waiting_on='"owner: later"'),
        ]
        self.assertEqual(lines(query.next_steps(docs)), [
            ("ask", "ask1", "owner: which colour"),
            ("blocked", "dep", "ask1"),
            ("work", "free", "planned"),
        ])

    def test_skips_docs_other_sessions_own(self):
        docs = [make("theirs", 10, owner="other-1"), make("mine", 20, owner="me-1"), make("free", 30)]
        self.assertEqual(lines(query.next_steps(docs, "me-1")), [("work", "mine", "planned")])
        self.assertEqual(lines(query.next_steps(docs, None)), [("work", "free", "planned")])

    def test_skips_a_doc_another_session_of_the_same_name_owns(self):
        def owned(session_id, pid):
            doc = make("owned", 10, owner="me-1")
            return parse.Doc(doc.path, doc.text.replace("---\n#", f"owner_session_id: {session_id}\nowner_session_pid: {pid}\n---\n#"))

        def next_ids(doc, caller):
            return [step.doc.id for step in query.next_steps([doc, make("free", 20)], caller)]

        clash = owned("id-a", 100)
        self.assertEqual(next_ids(clash, validate.Caller("me-1", "id-b", 200)), ["free"])
        # After a `/clear` (same pid) or a resume (same id) the owner still matches.
        self.assertEqual(next_ids(clash, validate.Caller("me-1", "id-new", 100)), ["owned"])
        self.assertEqual(next_ids(clash, validate.Caller("me-1", "id-a", 300)), ["owned"])
        # A human shell has no values and matches by name.
        self.assertEqual(next_ids(clash, validate.Caller("me-1")), ["owned"])
        self.assertEqual(next_ids(clash, "me-1"), ["owned"])
        # One empty value proves nothing, so it is no clash.
        self.assertEqual(next_ids(owned("id-a", '""'), validate.Caller("me-1", "id-b", 200)), ["owned"])
        self.assertEqual(next_ids(owned('""', 100), validate.Caller("me-1", "id-b", 200)), ["owned"])

    def test_finished_dependencies(self):
        docs = [make("needs", 10, depends_on="[done-dep, gone-dep]"), make("done-dep", 50, status="done")]
        self.assertEqual(lines(query.next_steps(docs)), [("work", "needs", "planned")])

    def test_unfinished_dependency_of_any_kind_blocks(self):
        docs = [make("needs", 10, depends_on="[later]"), make("later", 20, status="approved")]
        self.assertEqual(lines(query.next_steps(docs)), [("blocked", "needs", "later"), ("work", "later", "approved")])

    def test_no_free_doc(self):
        docs = [make("a", 10, waiting_on="owner"), make("b", 20, status="review")]
        self.assertEqual(lines(query.next_steps(docs)), [("ask", "a", "owner")])

    def test_all_lists_every_free_doc_in_rank_order(self):
        docs = [make("c", 30, status="approved"), make("a", 10), make("b", 20, status="building"), make("idea", 5, status="idea")]
        self.assertEqual(lines(query.next_steps(docs, all=True)),
                         [("work", "a", "planned"), ("work", "b", "building"), ("work", "c", "approved")])
        self.assertEqual(lines(query.next_steps(docs)), [("work", "a", "planned")])

    def test_all_skips_other_owners_and_blocks_dependents_of_free_docs(self):
        docs = [make("theirs", 10, owner="other-1"), make("base", 20), make("dep", 30, depends_on="[base]"),
                make("ask", 40, waiting_on="owner"), make("last", 50)]
        self.assertEqual(lines(query.next_steps(docs, "me-1", all=True)), [
            ("work", "base", "planned"),
            ("blocked", "dep", "base"),
            ("ask", "ask", "owner"),
            ("work", "last", "planned"),
        ])

    def test_all_honours_skip_and_unreadable_dependencies(self):
        docs = [make("one", 10), make("two", 20), make("needs", 30, depends_on="[lost]")]
        self.assertEqual(lines(query.next_steps(docs, skip={"one"}, unreadable_ids={"lost"}, all=True)),
                         [("work", "two", "planned"), ("blocked", "needs", "lost (unreadable)")])


if __name__ == "__main__":
    unittest.main()
