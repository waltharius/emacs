"""Tests of tools/check_module_graph.py: what the advisory report counts.

Run with hooks/check-all, or:

    python3 -B -m unittest discover -s tests/hooks -v
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "tools"))
import check_module_graph as graph  # noqa: E402


def mod(name, code, requires=""):
    """A module file NAME.el with CODE and its MyPKS-Requires."""
    return (name + ".el",
            f";;; {name}.el --- x -*- lexical-binding: t; -*-\n"
            f";; MyPKS-Requires: {requires}\n;; MyPKS-Optional: yes\n"
            f";;; Commentary:\n;;; Code:\n{code}\n(provide '{name})\n")


class Report(unittest.TestCase):

    def test_hard_cycle_found_guarded_one_not(self):
        """Two modules calling each other unguarded depend on each other;
        a pair whose uses are guarded by fboundp does not."""
        files = dict([
            mod("01-a", "(defun my/a () (my/b))"),
            mod("02-b", "(defun my/b () (my/a))"),
            mod("03-c", "(defun my/c () (when (fboundp 'my/d) (my/d)))"),
            mod("04-d", "(defun my/d () (when (fboundp 'my/c) (my/c)))"),
        ])
        self.assertEqual(graph.report(files, {})["cycles"], [["01-a", "02-b"]])

    def test_up_the_groups_hard_only(self):
        """A hard use of a higher group is reported; a guarded one is only
        counted."""
        files = dict([
            mod("01-a", "(defun my/a () (my/b) (when (fboundp 'my/c) (my/c)))"),
            mod("02-b", "(defun my/b () t)"),
            mod("03-c", "(defun my/c () t)"),
        ])
        r = graph.report(files, {"01-a": 100, "02-b": 200, "03-c": 300})
        self.assertEqual(r["up"], [("01-a", "02-b", ["my/b"])])
        self.assertEqual(r["guarded_up"], 1)

    def test_instability_and_sdp(self):
        """I = Ce/(Ca+Ce) over hard uses; a module used by two that uses a
        module using two others depends on a less stable one."""
        files = dict([
            mod("01-p", "(defun my/p () (my/s))"),
            mod("02-q", "(defun my/q () (my/s))"),
            mod("03-s", "(defun my/s () (my/u))"),
            mod("04-u", "(defun my/u () (my/v) (my/w))"),
            mod("05-v", "(defun my/v () t)"),
            mod("06-w", "(defun my/w () t)"),
        ])
        r = graph.report(files, {})
        self.assertEqual(r["stability"]["03-s"][:2], (2, 1))
        self.assertAlmostEqual(r["stability"]["03-s"][2], 1 / 3)
        self.assertIsNone(graph.report(dict([mod("07-x", "")]), {})["stability"]["07-x"][2])
        self.assertEqual([(a, b) for a, _, b, _ in r["sdp"]], [("03-s", "04-u")])

    def test_character_literal_hides_nothing(self):
        """A ?\\" character before a definition does not hide it: the first
        version of the script lost whole functions to it."""
        files = dict([
            mod("01-d", "(defvar my/d-pairs '((?\\\" . ?\\\")))\n(defun my/d () t)"),
            mod("02-e", "(defun my/e () (my/d))"),
        ])
        self.assertEqual(graph.report(files, {})["stability"]["01-d"][:2], (1, 0))

    def test_unexplained_requires(self):
        """A required module whose symbols are never used is listed; one
        used only guarded is not."""
        files = dict([
            mod("01-a", "(defun my/a () t)"),
            mod("02-b", "(defun my/b () t)"),
            mod("03-c", "(defun my/c () (when (fboundp 'my/b) (my/b)))", "01-a 02-b"),
        ])
        self.assertEqual(graph.report(files, {})["unused"], [("03-c", "01-a")])


if __name__ == "__main__":
    unittest.main()
