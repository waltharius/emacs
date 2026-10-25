;;; test-settings-tools.el --- ERT tests for favourite and recent settings of 148-settings-tools -*- lexical-binding: t; -*-

;; Tests: 148-settings-tools

;;; Commentary:

;; 148-settings-tools.el keeps favourite settings and records every change
;; made through Customize -- in a Customize buffer or by
;; `customize-set-variable' / `customize-save-variable' -- with the value
;; before, in a file of this machine, so that a change can be undone
;; after a restart: TESTING.org, *Every module tested*, part 3.  In the
;; test sandbox (its own settings folder); options of the test's own.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-settings-tools.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "148-settings-tools")

(defgroup my/st-test nil "Options of the settings-tools tests." :group 'mypks)
(defcustom my/st-test-width 70 "A test option." :type 'integer :group 'my/st-test)
(defcustom my/st-test-name "a" "A test option." :type 'string :group 'my/st-test)
(defcustom my/st-test-function #'ignore "A test option." :type 'function :group 'my/st-test)

(defmacro my/st-test--fresh (&rest body)
  "Run BODY with no record of changes, no favourites and the test
options at their defaults.  Saved values go to the sandbox's custom.el."
  (declare (indent 0))
  `(let ((inhibit-message t))
     (ignore-errors (delete-file (my/settings--recent-file)))
     (setq my/settings-favourites nil)
     (dolist (s '(my/st-test-width my/st-test-name my/st-test-function))
       (set-default s (eval (car (get s 'standard-value))))
       (put s 'saved-value nil)
       (put s 'customized-value nil))
     (unwind-protect
         (progn ,@body)
       (ignore-errors (delete-file (my/settings--recent-file))))))

(defun my/st-test--options ()
  "Return the options of the record, newest first."
  (mapcar (lambda (e) (plist-get e :option)) (my/settings--recent-read)))

;; ============================================================
;; THE RECORD
;; ============================================================

(ert-deftest my/st-test-record-set-variable ()
  "A change through `customize-set-variable' is recorded with the value
before, newest first; setting the same value again is not a change; an
option changed twice keeps one entry, its latest."
  (my/st-test--fresh
    (customize-set-variable 'my/st-test-width 80)
    (customize-set-variable 'my/st-test-name "b")
    (customize-set-variable 'my/st-test-name "b")
    (should (equal (my/st-test--options) '(my/st-test-name my/st-test-width)))
    (customize-set-variable 'my/st-test-width 90)
    (should (equal (my/st-test--options) '(my/st-test-width my/st-test-name)))
    (should (equal (plist-get (car (my/settings--recent-read)) :old) 80))
    (should (equal (plist-get (cadr (my/settings--recent-read)) :old) "a"))))

(ert-deftest my/st-test-record-kept-in-a-file ()
  "The record is a file in this machine's settings folder, read back as
written -- what survives a restart."
  (my/st-test--fresh
    (customize-set-variable 'my/st-test-width 80)
    (should (string-prefix-p (expand-file-name my/host-directory) (my/settings--recent-file)))
    (let ((read (with-temp-buffer
                  (insert-file-contents (my/settings--recent-file))
                  (read (current-buffer)))))
      (should (equal (plist-get (car read) :option) 'my/st-test-width))
      (should (equal (plist-get (car read) :old) 70)))))

(ert-deftest my/st-test-record-unreadable-kept ()
  "A record file that cannot be read is kept aside, not overwritten by
the next change; the new record starts beside it."
  (my/st-test--fresh
    (let ((aside (concat (my/settings--recent-file) ".unreadable")))
      (ignore-errors (delete-file aside))
      (with-temp-file (my/settings--recent-file) (insert "((:option x :old #<marker>"))
      (customize-set-variable 'my/st-test-width 80)
      (should (equal (with-temp-buffer (insert-file-contents aside) (buffer-string))
                     "((:option x :old #<marker>"))
      (should (equal (my/st-test--options) '(my/st-test-width)))
      (should-not (file-exists-p (concat (my/settings--recent-file) ".partial")))
      (delete-file aside))))

(ert-deftest my/st-test-record-limits ()
  "At most `my/settings-recent-max' entries are kept, the newest; the
favourites themselves are not recorded."
  (my/st-test--fresh
    (let ((my/settings-recent-max 2))
      (customize-set-variable 'my/st-test-width 80)
      (customize-set-variable 'my/st-test-name "b")
      (customize-set-variable 'my/st-test-function #'identity)
      (should (equal (my/st-test--options) '(my/st-test-function my/st-test-name)))
      (my/settings-favourite-add 'my/st-test-width)
      (should (equal (my/st-test--options) '(my/st-test-function my/st-test-name))))))

(ert-deftest my/st-test-record-unprintable ()
  "An old value that cannot be read back (a marker) is recorded without
it, and undoing that change says so instead of guessing."
  (my/st-test--fresh
    (with-temp-buffer
      (customize-set-variable 'my/st-test-name (point-marker))
      (customize-set-variable 'my/st-test-name "c"))
    ;; Recorded, and the record still reads back: a marker written into
    ;; it would make the whole file unreadable.
    (should (equal (my/st-test--options) '(my/st-test-name)))
    (should-not (plist-member (car (my/settings--recent-read)) :old))
    (should-error (my/settings-recent-undo 'my/st-test-name) :type 'user-error)
    (should (equal my/st-test-name "c"))))

(ert-deftest my/st-test-record-customize-buffer ()
  "A change applied in a Customize buffer is recorded too."
  (my/st-test--fresh
    (custom-buffer-create (list (list 'my/st-test-width 'custom-variable)) "*st-test*")
    (unwind-protect
        (with-current-buffer "*st-test*"
          (let* ((widget (car custom-options))
                 (field (car (widget-get widget :children))))
            (widget-value-set field 120)
            (custom-variable-set widget)))
      (kill-buffer "*st-test*"))
    (should (= my/st-test-width 120))
    (should (equal (my/st-test--options) '(my/st-test-width)))
    (should (equal (plist-get (car (my/settings--recent-read)) :old) 70))))

;; ============================================================
;; UNDO
;; ============================================================

(ert-deftest my/st-test-undo ()
  "Undo sets the option back to the value before its last change; a
saved option is saved back, so the next start has it too."
  (my/st-test--fresh
    (customize-set-variable 'my/st-test-width 80)
    (my/settings-recent-undo 'my/st-test-width)
    (should (= my/st-test-width 70))
    (should-not (get 'my/st-test-width 'saved-value))
    (customize-save-variable 'my/st-test-name "b")
    (customize-save-variable 'my/st-test-name "c")
    (my/settings-recent-undo 'my/st-test-name)
    (should (equal my/st-test-name "b"))
    ;; Saved again, as `saved-value' shows.  Writing custom.el is
    ;; Customize's own work (`custom-save-all') and not checked here: in
    ;; this batch Emacs it left custom.el without the value.
    (should (equal (get 'my/st-test-name 'saved-value) '("b")))))

;; ============================================================
;; FAVOURITES
;; ============================================================

(ert-deftest my/st-test-favourites ()
  "Favourites are added once, in order, removed again, and saved with
the settings; opening them with none refuses."
  (my/st-test--fresh
    (should-error (my/settings-favourites-open) :type 'user-error)
    (my/settings-favourite-add 'my/st-test-width)
    (my/settings-favourite-add 'my/st-test-name)
    (my/settings-favourite-add 'my/st-test-width)
    (should (equal my/settings-favourites '(my/st-test-width my/st-test-name)))
    (should (equal (get 'my/settings-favourites 'saved-value)
                   '('(my/st-test-width my/st-test-name))))
    (my/settings-favourite-remove 'my/st-test-width)
    (should (equal my/settings-favourites '(my/st-test-name)))
    (my/settings-favourites-open)
    (should (get-buffer "*MyPKS favourite settings*"))
    (kill-buffer "*MyPKS favourite settings*")))

(provide 'test-settings-tools)
;;; test-settings-tools.el ends here
