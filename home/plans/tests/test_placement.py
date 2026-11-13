"""The shared rank math: the midpoint between two ranks and the renumber of the docs around a new slot."""

import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PACKAGE, ".local", "lib", "plans"))
from plans import parse, placement  # noqa: E402


class RankBetweenTest(unittest.TestCase):
    def test_rank_between(self):
        cases = [((None, 30), 20), ((None, 5), 2), ((None, 0), None), ((10, None), 20), ((10, 20), 15), ((10, 11), None),
                 ((10, 10), None)]
        for (above, below), expected in cases:
            self.assertEqual(placement.rank_between(above, below), expected, (above, below))


class RenumberTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

    def doc(self, name, rank):
        path = os.path.join(self.temp.name, ".plans", "p", name + ".md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        keys = "".join(f"{key}: {value}\n" for key, value in (
            ("id", name), ("project", "p"), ("kind", "feature"), ("status", "idea"), ("owner_session", "none"),
            ("rank", rank), ("depends_on", "[]"), ("waiting_on", '""'), ("issue", "none"), ("pr", "none"),
            ("branch", "none"), ("fix_rounds", 0), ("updated", '"2026-11-01"')))
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(f"---\n{keys}---\n# {name}\n")
        return parse.load(path)

    def test_ranks_run_in_steps_of_ten_in_order(self):
        order = [self.doc("a", 1), self.doc("b", 2)]
        self.assertEqual(list(placement.renumbered_ranks(order).values()), [10, 20])

    def test_others_are_written_and_the_moved_doc_and_a_refused_doc_are_not(self):
        class Refuse(Exception):
            pass

        def check(doc):
            if doc.id == "c":
                raise Refuse("owned elsewhere")

        moved, a, c = self.doc("m", 5), self.doc("a", 6), self.doc("c", 7)
        order = [a, moved, c]
        ranks = placement.renumbered_ranks(order)
        written, skipped, uncertain = placement.renumber_others(order, moved, ranks, check, (Refuse,))
        self.assertEqual((written, [entry["id"] for entry in skipped], uncertain), (1, ["c"], []))
        self.assertEqual([parse.load(doc.path).keys["rank"] for doc in (a, moved, c)], [10, 5, 7])


if __name__ == "__main__":
    unittest.main()
