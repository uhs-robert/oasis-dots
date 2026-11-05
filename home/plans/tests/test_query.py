"""ls filters and order, waiting, questions, and the ask/blocked/work lines of next."""

import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import parse, query  # noqa: E402


def make(doc_id, rank, status="planned", owner="none", waiting_on='""', depends_on="[]", project="proj", questions=""):
    head = (f"id: {doc_id}\nproject: {project}\nkind: feature\nstatus: {status}\nowner_session: {owner}\nrank: {rank}\n"
            f"depends_on: {depends_on}\nwaiting_on: {waiting_on}\n")
    body = f"# {doc_id}\n\n## Open questions\n\n{questions}\n## Owner checks\n"
    return parse.Doc(f"/r/.plans/{project}/{doc_id}.md", f"---\n{head}---\n{body}")


def ids(docs):
    return [doc.id for doc in docs]


def lines(steps):
    return [(step.action, step.doc.id, step.detail) for step in steps]


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

    def test_finished_dependencies(self):
        docs = [make("needs", 10, depends_on="[done-dep, gone-dep]"), make("done-dep", 50, status="done")]
        self.assertEqual(lines(query.next_steps(docs)), [("work", "needs", "planned")])

    def test_unfinished_dependency_of_any_kind_blocks(self):
        docs = [make("needs", 10, depends_on="[later]"), make("later", 20, status="approved")]
        self.assertEqual(lines(query.next_steps(docs)), [("blocked", "needs", "later"), ("work", "later", "approved")])

    def test_no_free_doc(self):
        docs = [make("a", 10, waiting_on="owner"), make("b", 20, status="review")]
        self.assertEqual(lines(query.next_steps(docs)), [("ask", "a", "owner")])


if __name__ == "__main__":
    unittest.main()
