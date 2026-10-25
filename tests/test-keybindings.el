;;; test-keybindings.el --- ERT tests for the keybinding help of 208-keybindings -*- lexical-binding: t; -*-

;; Tests: 208-keybindings

;;; Commentary:

;; `my/show-keybindings-help' (C-c h k) shows the help text.  From
;; 2026-09-12 to 2026-10-22 the text held an unescaped "quoted phrase":
;; the string ended there, the `let' got five values instead of one, and
;; C-c h k stopped with "`let' bindings can have only one value-form".
;; Found by the weekly byte compilation ("Malformed `let' binding").
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-keybindings.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
;; Only what the help command needs; 101-ui, also required by the
;; module's header, sets up the interface and is not needed here.
(my/test-load-modules "205-notes" "212-transient" "208-keybindings")

(ert-deftest my/keys-test-help-shows-whole-text ()
  "C-c h k shows the help text, from its title to its last line."
  (unwind-protect
      (progn
        (my/show-keybindings-help)
        (with-current-buffer "*Keybindings Help*"
          (let ((text (buffer-string)))
            (should (string-prefix-p "Keybindings Summary" text))
            (should (string-match-p "g takes a query: \"quoted phrase\"" text))
            (should (string-match-p "function_helper.org\n*\\'" text)))))
    (when (get-buffer "*Keybindings Help*")
      (kill-buffer "*Keybindings Help*"))))

(provide 'test-keybindings)
;;; test-keybindings.el ends here
