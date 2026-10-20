;;; test-session.el --- ERT tests for what a restart brings back -*- lexical-binding: t; -*-

;;; Commentary:

;; Three things seen after a restart on 2026-10-19:
;;
;; - a split showing " *Old buffer *Warnings**": Emacs 30 puts a
;;   placeholder in a tab's window whose buffer was killed;
;;   `my/tab-bar-restore-windows' (01-ui.el) closes such a window unless
;;   the buffer visited a file;
;; - setters of saved options run again when a theme loads, as if
;;   changed by hand; `my/settings--live-p' (00-core.el) is nil while a
;;   theme is enabled;
;; - old files left in ~/.emacs.d next to their new copies;
;;   `my/var--trash-old' moves them to the trash.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-session.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; An Emacs built without graphical support has no scroll bars; 01-ui.el
;; turns them off at load.
(unless (fboundp 'scroll-bar-mode)
  (defalias 'scroll-bar-mode #'ignore))

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "01-ui")

;; ============================================================
;; WINDOWS OF KILLED BUFFERS
;; ============================================================

(ert-deftest my/session-test-killed-buffer-window-closed ()
  "The window of a killed buffer that visited no file is closed."
  (delete-other-windows)
  (let* ((window (split-window))
         (buffer (get-buffer-create "*Warnings-test*")))
    (set-window-buffer window buffer)
    (kill-buffer buffer)
    (my/tab-bar-restore-windows (selected-frame) (list (list window buffer 1 1 nil nil)) nil)
    (should-not (window-live-p window))
    (should (one-window-p t))))

(ert-deftest my/session-test-file-window-kept ()
  "The window of a killed file buffer stays, for Emacs's [Restore]."
  (delete-other-windows)
  (let* ((file (make-temp-file "mypks-session-"))
         (window (split-window))
         (buffer (find-file-noselect file)))
    (set-window-buffer window buffer)
    ;; Emacs's own placeholder (Emacs 30) is not what is tested here.
    (cl-letf (((symbol-function 'tab-bar-select-restore-windows) #'ignore))
      (my/tab-bar-restore-windows (selected-frame) (list (list window buffer 1 1 nil nil)) nil))
    (should (window-live-p window))
    (kill-buffer buffer)
    (delete-file file)
    (delete-other-windows)))

(ert-deftest my/session-test-only-window-kept ()
  "The only window of the frame is never closed."
  (delete-other-windows)
  (let ((buffer (get-buffer-create "*Only-test*")))
    (set-window-buffer (selected-window) buffer)
    (kill-buffer buffer)
    (my/tab-bar-restore-windows (selected-frame)
                                (list (list (selected-window) buffer 1 1 nil nil)) nil)
    (should (window-live-p (selected-window)))))

;; ============================================================
;; SETTERS WHILE A THEME LOADS
;; ============================================================

(defvar my/session-test--seen nil
  "What `my/settings--live-p' said in each call of the test option's setter.")

(defcustom my/session-test-option nil
  "An option whose setter records whether it counted as a change."
  :type 'sexp
  :group 'mypks
  :set (lambda (symbol value)
         (push (my/settings--live-p) my/session-test--seen)
         (set-default-toplevel-value symbol value)))

(ert-deftest my/session-test-theme-is-no-change ()
  "A saved option handed back by `enable-theme' is not a change by hand."
  (let ((after-init-time (or after-init-time (current-time)))
        (load-file-name nil))
    (setq my/session-test--seen nil)
    (customize-set-variable 'my/session-test-option 1)
    (should (equal my/session-test--seen '(t)))
    (custom-set-variables '(my/session-test-option 2))
    (setq my/session-test--seen nil)
    (enable-theme 'user)
    (should my/session-test--seen)
    (should-not (memq t my/session-test--seen))))

;; ============================================================
;; OLD FILES TO THE TRASH
;; ============================================================

(ert-deftest my/session-test-old-files-trashed ()
  "Old files and folders go to the trash, whole; the new ones stay.
Until 2026-10-20 this checked only that the old ones were gone, which a
plain deletion passes too (audit of that date); now their content must
be in the trash."
  (let* ((dir (make-temp-file "mypks-old-" t))
         (trash (make-temp-file "mypks-trash-" t))
         (trash-directory trash)
         (old (expand-file-name "saveplace" dir))
         (folder (expand-file-name "persist" dir))
         (new (expand-file-name "save-place.el" dir)))
    (with-temp-file old (insert "old"))
    (make-directory folder)
    (with-temp-file (expand-file-name "x" folder) (insert "x"))
    (with-temp-file new (insert "new"))
    (cl-letf (((symbol-function 'my/notes-report) #'ignore))
      (my/var--trash-old (list old folder)))
    (should-not (file-exists-p old))
    (should-not (file-exists-p folder))
    (should (file-exists-p new))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "saveplace" trash))
      (should (equal (buffer-string) "old")))
    (should (file-exists-p (expand-file-name "persist/x" trash)))
    (delete-directory dir t)
    (delete-directory trash t)))

(provide 'test-session)
;;; test-session.el ends here
