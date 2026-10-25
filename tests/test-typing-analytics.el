;;; test-typing-analytics.el --- ERT tests for the keystroke log of 14-typing-analytics -*- lexical-binding: t; -*-

;; Tests: 14-typing-analytics

;;; Commentary:

;; 14-typing-analytics logs typed characters with their time, when the
;; owner turns the log on, to collect data for choosing a keyboard.
;; The log is a plain-text copy of the writing, so what matters most is
;; what it leaves out: the minibuffer, and notes of a private silo --
;; also through an indirect buffer, such as an org-capture into the
;; journal.  These tests type through `self-insert-command' and
;; `newline', with `post-self-insert-hook' as in a real session, and
;; read the log file: its two-field lines, when it is written, the
;; switches, the idle timer.  keyfreq, the command counter, is the
;; package's own business and not tested here.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-typing-analytics.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "14-typing-analytics")

(defmacro my/ta-test-with-log (&rest body)
  "Run BODY with the log on, in a temporary file and notes folder.
The log is turned off and its timer stopped afterwards."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "mypks-ta-" t))
          (my-notes-dir (file-name-as-directory (expand-file-name "notes" dir)))
          (my/keylog-file (expand-file-name "keys" dir))
          (my/keylog-buffer nil)
          (my/keylog--count 0)
          (my/keylog-last-save-time (current-time))
          (my/keylog-buffer-size 1000)
          (my/keylog-autosave-interval 3600)
          (my/keylog--timer nil)
          (post-self-insert-hook nil)
          (kill-emacs-hook kill-emacs-hook))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "journal" my-notes-dir) t)
           (make-directory (expand-file-name "pks" my-notes-dir) t)
           (my/keylog-enable)
           ,@body)
       (my/keylog-disable)
       (delete-directory dir t))))

(defun my/ta-test-type (text)
  "Type TEXT in the current buffer, one self-inserting command per character."
  (dolist (char (string-to-list text))
    (let ((last-command-event char))
      (self-insert-command 1))))

(defun my/ta-test-log-lines (&optional unsaved)
  "Write what is collected, return the lines of the log file.
With UNSAVED, read the file as it is, without writing first."
  (unless unsaved (my/keylog-save-buffer))
  (if (file-exists-p my/keylog-file)
      (with-temp-buffer
        (insert-file-contents my/keylog-file)
        (split-string (buffer-string) "\n" t))
    nil))

(defun my/ta-test-logged-keys ()
  "The second field of each line of the log."
  (mapcar (lambda (line) (cadr (split-string line "\t"))) (my/ta-test-log-lines)))

(ert-deftest my/ta-test-typed-characters-logged ()
  "Each typed character is a line: a time, a tab, the character."
  (my/ta-test-with-log
    (with-temp-buffer
      (my/ta-test-type "ał b"))
    (let ((lines (my/ta-test-log-lines)))
      (should (= (length lines) 4))
      (dolist (line lines)
        (should (string-match-p "\\`[0-9]+\\.[0-9]\\{6\\}\t.\\'" line)))
      (should (equal (my/ta-test-logged-keys) '("a" "ł" " " "b"))))))

(ert-deftest my/ta-test-newline-one-line-of-two-fields ()
  "A newline typed is logged by its key name, on one line of two fields;
it was written raw and split the line in two."
  (my/ta-test-with-log
    (with-temp-buffer
      (my/ta-test-type "a")
      (newline nil t)
      (my/ta-test-type "b"))
    (let ((lines (my/ta-test-log-lines)))
      (should (= (length lines) 3))
      (dolist (line lines)
        (should (= (length (split-string line "\t")) 2)))
      (should (equal (my/ta-test-logged-keys) '("a" "C-j" "b"))))))

(ert-deftest my/ta-test-private-silo-not-logged ()
  "Typing in a journal note is not logged; in a pks note it is."
  (my/ta-test-with-log
    (with-current-buffer (find-file-noselect
                          (expand-file-name "journal/20261025T100000--dzien.org" my-notes-dir))
      (my/ta-test-type "tajne")
      (set-buffer-modified-p nil)
      (kill-buffer))
    (with-current-buffer (find-file-noselect
                          (expand-file-name "pks/20261025T100000--notatka.org" my-notes-dir))
      (my/ta-test-type "x")
      (set-buffer-modified-p nil)
      (kill-buffer))
    (should (equal (my/ta-test-logged-keys) '("x")))))

(ert-deftest my/ta-test-indirect-buffer-of-private-note-not-logged ()
  "An indirect buffer of a journal note -- what org-capture types into --
is not logged either: it has no file name of its own."
  (my/ta-test-with-log
    (let* ((base (find-file-noselect
                  (expand-file-name "journal/captures.org" my-notes-dir)))
           (indirect (make-indirect-buffer base "CAPTURE-captures.org")))
      (unwind-protect
          (with-current-buffer indirect
            (should-not buffer-file-name)
            (my/ta-test-type "pomysl"))
        (kill-buffer indirect)
        (with-current-buffer base (set-buffer-modified-p nil))
        (kill-buffer base)))
    (should-not (my/ta-test-logged-keys))))

(ert-deftest my/ta-test-minibuffer-not-logged ()
  "What is typed in the minibuffer -- a password prompt among others --
is not logged."
  (my/ta-test-with-log
    (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t)))
      (with-temp-buffer (my/ta-test-type "haslo")))
    (should-not (my/ta-test-logged-keys))))

(ert-deftest my/ta-test-written-after-buffer-size ()
  "Collected keystrokes reach the file once `my/keylog-buffer-size' are
collected, not before."
  (my/ta-test-with-log
    (let ((my/keylog-buffer-size 3))
      (with-temp-buffer
        (my/ta-test-type "ab")
        (should-not (file-exists-p my/keylog-file))
        (my/ta-test-type "c")
        (should (file-exists-p my/keylog-file))
        (should (= my/keylog--count 0))))))

(ert-deftest my/ta-test-written-while-typing-after-interval ()
  "Continuous typing is written once `my/keylog-autosave-interval'
seconds have passed since the last write."
  (my/ta-test-with-log
    (let ((my/keylog-autosave-interval 60))
      (setq my/keylog-last-save-time (time-subtract (current-time) 61))
      (with-temp-buffer (my/ta-test-type "a"))
      (should (file-exists-p my/keylog-file)))))

(ert-deftest my/ta-test-enable-twice-one-timer ()
  "Turning the log on twice starts one idle timer, not two; off stops
it, writes what was collected and takes the hooks away."
  (my/ta-test-with-log
    (let ((timer my/keylog--timer))
      (my/keylog-enable)
      (should (eq my/keylog--timer timer))
      (should (memq timer timer-idle-list))
      (with-temp-buffer (my/ta-test-type "z"))
      (my/keylog-disable)
      (should-not (memq timer timer-idle-list))
      (should-not my/keylog--timer)
      (should-not (memq #'my/keylog-record-keystroke post-self-insert-hook))
      (should-not (memq #'my/keylog-save-buffer kill-emacs-hook))
      ;; Read without writing first: the switch itself must have written.
      (should (equal (mapcar (lambda (line) (cadr (split-string line "\t")))
                             (my/ta-test-log-lines t))
                     '("z"))))))

(ert-deftest my/ta-test-idle-delay-change-restarts-timer ()
  "A new idle delay restarts the running timer with it."
  (my/ta-test-with-log
    (let ((old my/keylog--timer))
      (let ((my/keylog-idle-save-seconds 5))
        (my/keylog--restart-timer))
      (should-not (memq old timer-idle-list))
      (should (equal (timer--time my/keylog--timer) (time-convert 5 'list))))))

(ert-deftest my/ta-test-log-needs-option-and-switch ()
  "The log runs only while both `my/keylog-enabled' and the module's
switch are on."
  (let ((post-self-insert-hook nil)
        (my/keylog--timer nil)
        (kill-emacs-hook kill-emacs-hook)
        (my/keylog-buffer nil)
        (my/keylog-file (make-temp-file "mypks-ta-keys")))
    (unwind-protect
        (let ((my/keylog-enabled t))
          (my/keylog--apply)
          (should (memq #'my/keylog-record-keystroke post-self-insert-hook))
          (let ((my/typing-analytics-mode nil))
            (my/keylog--apply)
            (should-not (memq #'my/keylog-record-keystroke post-self-insert-hook)))
          (let ((my/keylog-enabled nil))
            (my/keylog--apply)
            (should-not (memq #'my/keylog-record-keystroke post-self-insert-hook))))
      (my/keylog-disable)
      (delete-file my/keylog-file))))

(provide 'test-typing-analytics)
;;; test-typing-analytics.el ends here
