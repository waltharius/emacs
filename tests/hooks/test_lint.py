"""Tests of hooks/lint.py: checks that cannot run say so, and do not pass.

Run with hooks/check-all, or:

    python3 -B -m unittest discover -s tests/hooks -v
"""

import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "hooks"))
import lint  # noqa: E402


class DiscoveryFailureIsASkip(unittest.TestCase):
    """Outside a git repository the file lists cannot be made (audit 2026-10-20)."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        patcher = mock.patch.object(lint, "ROOT", self.dir)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_repository_files(self):
        with self.assertRaises(lint.Skip):
            lint.repository_files()

    def test_code_folder(self):
        with self.assertRaises(lint.Skip):
            lint.check_code_folder()

    def test_staged_files(self):
        with self.assertRaises(lint.Skip):
            lint.staged_files()


class Changelog(unittest.TestCase):

    def check(self, staged):
        with mock.patch.object(lint, "staged_files", return_value=staged):
            return lint.check_changelog()

    def test_module_without_entry(self):
        self.assertTrue(self.check(["modules/05-notes.el"]))

    def test_module_with_entry(self):
        self.assertEqual([], self.check(["modules/05-notes.el", "CHANGELOG.md"]))

    def test_nothing_staged(self):
        self.assertEqual([], self.check([]))


if __name__ == "__main__":
    unittest.main()
