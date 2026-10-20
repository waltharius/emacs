"""Tests of hooks/module_contract.py: which uses of another module are guarded.

Every case is a provider module and a consumer module; the test says
whether the consumer's use of the provider is *hard* (must be declared
in MyPKS-Requires) or *guarded*.  The cases marked 'audit' were read
wrongly before 2026-10-20 (hook-audit-synthetic-reproductions.csv):
each now fails with the reader of that date, and passes with the fix.

Run with hooks/check-all, or:

    python3 -B -m unittest discover -s tests/hooks -v
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "hooks"))
import module_contract  # noqa: E402

PROVIDER = """
(defun my/a () nil)
(defun my/b () nil)
(defvar my/value nil)
(defvar my/path "somewhere")
(defvar my/char ?a)
(defvar my/declared)
(defvar my/x-hook nil)
(provide '10-a)
"""


def classify(consumer, provider=PROVIDER):
    """Return 'hard', 'guarded' or 'none' for the consumer's use of 10-a."""
    hard, guarded = module_contract.dependencies(
        {"10-a.el": provider, "20-b.el": consumer})
    if hard["20-b.el"].get("10-a.el"):
        return "hard"
    if guarded["20-b.el"].get("10-a.el"):
        return "guarded"
    return "none"


class Guarded(unittest.TestCase):
    """Uses that run only where a test has shown the provider present."""

    def check(self, code):
        self.assertEqual(classify(code), "guarded", code)

    def test_when_fboundp(self):
        self.check("(defun my/use () (when (fboundp 'my/a) (my/a)))")

    def test_if_then(self):
        self.check("(defun my/use () (if (fboundp 'my/a) (my/a) nil))")

    def test_if_not_else(self):
        self.check("(defun my/use () (if (not (fboundp 'my/a)) nil (my/a)))")

    def test_and_chain(self):
        self.check("(defun my/use () (and x (fboundp 'my/a) (my/a)))")

    def test_when_and(self):
        self.check("(defun my/use () (when (and x (fboundp 'my/a)) (my/a)))")

    def test_or_after_negated_test(self):
        self.check("(defun my/use () (or (not (fboundp 'my/a)) (my/a)))")

    def test_cond_clause(self):
        self.check("(defun my/use () (cond ((fboundp 'my/a) (my/a)) (t nil)))")

    def test_when_let_binding(self):
        self.check("(defun my/use () (when-let* ((ok (fboundp 'my/a))) (my/a)))")

    def test_let_binding_with_and(self):
        self.check("(defun my/use () (let ((v (and (fboundp 'my/a) (my/a)))) v))")

    def test_unless_then_leave(self):
        self.check("(defun my/use () (unless (fboundp 'my/a) (user-error \"no\")) (my/a))")

    def test_when_not_then_leave(self):
        self.check("(defun my/use () (when (not (fboundp 'my/a)) (error \"no\")) (my/a))")

    def test_after_load(self):
        self.check("(with-eval-after-load '10-a (my/a))")

    def test_featurep_guards_the_whole_module(self):
        self.check("(defun my/use () (when (featurep '10-a) (my/b)))")

    def test_quoted_variable_named(self):
        self.check("(add-hook 'my/x-hook #'ignore)")

    def test_quoted_in_data_call(self):
        self.check("(defun my/use (l) (remq 'my/a l))")


class Hard(unittest.TestCase):
    """Uses that run, or may run, without the provider."""

    def check(self, code):
        self.assertEqual(classify(code), "hard", code)

    def test_unguarded(self):
        self.check("(defun my/use () (my/a))")

    def test_if_else_branch(self):  # audit
        self.check("(defun my/use () (if (fboundp 'my/a) nil (my/a)))")

    def test_when_not(self):  # audit
        self.check("(defun my/use () (when (not (fboundp 'my/a)) (my/a)))")

    def test_or_with_true(self):  # audit
        self.check("(defun my/use () (when (or (fboundp 'my/a) t) (my/a)))")

    def test_guard_on_another_symbol(self):  # audit
        self.check("(defun my/use () (when (fboundp 'my/a) (my/b)))")

    def test_unless_that_only_warns(self):  # audit
        self.check("(defun my/use () (unless (fboundp 'my/a) (message \"missing\")) (my/a))")

    def test_symbol_value_of_quoted(self):  # audit
        self.check("(defun my/use () (symbol-value 'my/value))")

    def test_string_initialised_defvar(self):  # audit
        self.check("(defun my/use () my/path)")

    def test_char_initialised_defvar(self):
        self.check("(defun my/use () my/char)")

    def test_cond_later_clause(self):
        self.check("(defun my/use () (cond ((fboundp 'my/a) nil) (t (my/a))))")

    def test_if_let_else(self):
        self.check("(defun my/use () (if-let* ((ok (fboundp 'my/a))) nil (my/a)))")

    def test_after_load_of_another_module(self):
        self.check("(with-eval-after-load '30-c (my/a))")


class Definitions(unittest.TestCase):
    """What counts as defining a symbol."""

    def owned(self, code):
        top, _ = module_contract.parse(code)
        return [module_contract.defined(f) for f in module_contract.walk(top)]

    def test_defvar_with_string(self):  # audit
        self.assertIn(("my/path", "variable"), self.owned('(defvar my/path "somewhere")'))

    def test_defvar_with_char(self):
        self.assertIn(("my/c", "variable"), self.owned("(defvar my/c ?a)"))

    def test_bare_defvar_only_declares(self):
        self.assertEqual([None], self.owned("(defvar my/declared)"))

    def test_declared_variable_is_no_use(self):
        self.assertEqual("none", classify("(defvar my/declared) (defun my/use () nil)"))


if __name__ == "__main__":
    unittest.main()
