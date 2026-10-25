;;; test-frame-bars.el --- ERT tests for 01b-frame-bars -*- lexical-binding: t; -*-

;; Tests: 01b-frame-bars

;;; Commentary:

;; 01b-frame-bars turns the tool bar and the scroll bars off and keeps
;; the menu bar, at load and again after a desktop restore.  Tested: the
;; state after load; bars turned on by a restored frameset are turned
;; off again by `desktop-after-read-hook'; an Emacs without
;; `scroll-bar-mode' (emacs-nox) is not stopped.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-frame-bars.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "01b-frame-bars")

(ert-deftest my/fc-test-state-after-load ()
  "After load the tool bar is off and the menu bar on."
  (should-not tool-bar-mode)
  (should menu-bar-mode)
  (when (boundp 'scroll-bar-mode)
    (should-not scroll-bar-mode)))

(ert-deftest my/fc-test-bars-off-again-after-desktop-read ()
  "Bars a restored desktop turned on are turned off by the hook the
desktop runs after reading."
  (tool-bar-mode 1)
  (should tool-bar-mode)
  (run-hooks 'desktop-after-read-hook)
  (should-not tool-bar-mode))

(ert-deftest my/fc-test-no-scroll-bar-mode ()
  "Without `scroll-bar-mode', as in an Emacs built without a window
system, the bars are set without an error."
  (let ((saved (symbol-function 'scroll-bar-mode)))
    (unwind-protect
        (progn
          (fmakunbound 'scroll-bar-mode)
          (tool-bar-mode 1)
          (my/frame-bars-apply)
          (should-not tool-bar-mode))
      (fset 'scroll-bar-mode saved))))

(provide 'test-frame-bars)
;;; test-frame-bars.el ends here
