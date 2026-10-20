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


def fake_modules(files):
    """Patch lint.modules to yield FILES ({name: text})."""
    return mock.patch.object(lint, "modules", lambda: iter(sorted(files.items())))


MODULE = """;;; 20-b.el --- t -*- lexical-binding: t; -*-
;;; Code:
%s
"""


class Keys(unittest.TestCase):
    """The help text's keys must be bound by a binding form (audit 2026-10-20)."""

    def problems(self, code):
        keys_file = tempfile.NamedTemporaryFile(suffix=".el", delete=False)
        self.addCleanup(os.unlink, keys_file.name)
        with fake_modules({"20-b.el": MODULE % code}), \
                mock.patch.object(lint, "KEYS_FILE", keys_file.name), \
                mock.patch.object(lint, "help_text_keys",
                                  return_value=[("C-c x", "C-c x - do x")]):
            return lint.check_keybinding_help()

    def test_global_set_key(self):
        self.assertEqual([], self.problems('(global-set-key (kbd "C-c x") #\'my/x)'))

    def test_define_key(self):
        self.assertEqual([], self.problems('(define-key my/map (kbd "C-c x") #\'my/x)'))

    def test_keymap_set(self):
        self.assertEqual([], self.problems('(keymap-set global-map "C-c x" #\'my/x)'))

    def test_use_package_bind_pair(self):
        self.assertEqual([], self.problems('(use-package x :bind (("C-c x" . my/x)))'))

    def test_only_in_a_comment(self):  # audit
        self.assertTrue(self.problems(';; Old binding was "C-c x".'))

    def test_only_in_a_docstring(self):  # audit
        self.assertTrue(self.problems('(defun my/x () "Bound to \\"C-c x\\" once." nil)'))


class Functions(unittest.TestCase):
    """Every name of a Function line must exist (audit 2026-10-20)."""

    def problems(self, doc, known=("my/a", "my/a-one")):
        helper = tempfile.NamedTemporaryFile("w", suffix=".org", delete=False)
        helper.write(doc)
        helper.close()
        self.addCleanup(os.unlink, helper.name)
        with mock.patch.object(lint, "HELPER", helper.name), \
                mock.patch.object(lint, "definitions",
                                  return_value={k: [("x.el", 1)] for k in known}):
            return lint.check_documented_functions()

    def test_all_present(self):
        self.assertEqual([], self.problems("Function: =my/a= | Module: =x=\n"))

    def test_second_name_with_and(self):  # audit
        self.assertTrue(self.problems("Function: =my/a= and =my/b=\n"))

    def test_second_name_with_comma(self):
        self.assertTrue(self.problems("Function: =my/a=, =my/b= | Module: =x=\n"))

    def test_plural(self):
        self.assertTrue(self.problems("Functions: =my/b= | Module: =x=\n"))

    def test_continuation_line(self):
        self.assertTrue(self.problems("Function: =my/a=,\n=my/b= | Module: =x=\n"))

    def test_after_the_bar_not_read(self):
        self.assertEqual([], self.problems("Function: =my/a= | Variable: =my/zzz=\n"))

    def test_family(self):
        self.assertEqual([], self.problems("Functions: =my/a-*= | Module: =x=\n"))


class Definitions(unittest.TestCase):

    def test_forms(self):
        code = "\n".join(["(defsubst my/s () nil)", "(cl-defmacro my/m () nil)",
                          "(defface my/f nil \"f\")", "(define-inline my/i () nil)"])
        with fake_modules({"20-b.el": MODULE % code}):
            found = lint.definitions()
        for sym in ("my/s", "my/m", "my/f", "my/i"):
            self.assertIn(sym, found)


if __name__ == "__main__":
    unittest.main()
