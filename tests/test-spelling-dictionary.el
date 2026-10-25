;;; test-spelling-dictionary.el --- ERT tests for the personal dictionary of 303-spelling -*- lexical-binding: t; -*-

;; Tests: 303-spelling

;;; Commentary:
;; The personal dictionary in the settings folder: reading Hunspell's
;; format, merging old files into the new one, the merge=union
;; attribute, the once-per-machine import, and what a changed file
;; tells the running Hunspell.
;;
;; Runs without the rest of the configuration and without packages, from
;; the repository's folder:
;;
;;   emacs -Q --batch -l tests/test-spelling-dictionary.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; Every test works in a temporary folder; ~/.hunspell_personal and the
;; real settings folder are never read or written.  The file watch
;; itself is not tested here (inotify events reach batch Emacs only
;; through `read-event'); TESTPLAN.org covers it by hand.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ============================================================
;; STAND-INS FOR 000-core.el
;; ============================================================
;; Only what 303-spelling.el uses at load, pointed at a temporary
;; folder.  With the real core loaded they are left alone.

(defconst my/spell-test--root (make-temp-file "mypks-spell-" t)
  "Temporary folder for the whole run.")

(unless (featurep '000-core)
  (defconst my/settings-directory
    (file-name-as-directory (expand-file-name "settings" my/spell-test--root)))
  (defconst my/host-directory
    (file-name-as-directory (expand-file-name "hosts/test" my/settings-directory)))
  (defun my/settings-apply-on-set (function)
    "Stand-in: store the value; call FUNCTION outside of loading."
    (lambda (symbol value)
      (set-default-toplevel-value symbol value)
      (when (and after-init-time (not load-file-name) (fboundp function))
        (funcall function))))
  (defun my/notes-report (kind title lines &optional _choices)
    "Stand-in: record the report in `my/spell-test--reports'."
    (push (list kind title lines) my/spell-test--reports)))

(defvar my/spell-test--reports nil
  "Reports shown through the stand-in `my/notes-report'.")

;; Special here as well, so that the `let's below bind what the module
;; reads: a bare `defvar' in 303-spelling.el is local to that file.
(defvar ispell-process)
(defvar ispell-personal-dictionary)

(require 'use-package)
(setq use-package-always-ensure nil
      use-package-ensure-function #'ignore)

(load (expand-file-name "../modules/300-notes-core/303-spelling.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

;; ============================================================
;; HELPERS
;; ============================================================

(defun my/spell-test--write (file text)
  "Write TEXT to FILE, creating its folder."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file file (insert text))))

(defun my/spell-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defmacro my/spell-test--with-folder (&rest body)
  "Run BODY with a fresh dictionary, state file and old dictionary.
Binds `target' and `legacy' to the new and the old file."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "case-" t nil))
          (target (expand-file-name "settings/dictionaries/hunspell_personal" dir))
          (legacy (expand-file-name "home/.hunspell_personal" dir))
          (my/host-directory (file-name-as-directory (expand-file-name "settings/hosts/test" dir)))
          (my/spell--legacy-dictionary legacy)
          (my/spell-personal-dictionary target)
          (my/spell-test--reports nil))
     (ignore target legacy)
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

;; ============================================================
;; FORMAT
;; ============================================================

(ert-deftest my/spell-test-lines-drop-header-and-blanks ()
  "The aspell header and empty lines are not entries."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "personal_ws-1.1 pl_PL 0 utf-8\nzażółć\n\nDenote  \n")
    (should (equal (my/spell--dictionary-lines legacy) '("zażółć" "Denote")))))

(ert-deftest my/spell-test-lines-missing-file ()
  "A missing file has no entries."
  (should (null (my/spell--dictionary-lines
                 (expand-file-name "nothing-here" my/spell-test--root)))))

;; ============================================================
;; MERGE
;; ============================================================

(ert-deftest my/spell-test-merge-creates-target ()
  "Merging into a missing file creates it with the old entries."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "personal_ws-1.1 pl_PL 0 utf-8\nzażółć\nDenote\n")
    (should (= 2 (my/spell--dictionary-merge legacy target)))
    (should (equal (my/spell-test--read target) "zażółć\nDenote\n"))))

(ert-deftest my/spell-test-merge-appends-missing-only ()
  "Only entries the target lacks are added, after its own, in order."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\nbeta\n")
    (my/spell-test--write legacy "beta\ngamma\n*zle\n")
    (should (= 2 (my/spell--dictionary-merge legacy target)))
    (should (equal (my/spell-test--read target) "alfa\nbeta\ngamma\n*zle\n"))))

(ert-deftest my/spell-test-merge-leaves-source-alone ()
  "The old file is only read."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "personal_ws-1.1 pl_PL 0 utf-8\nzażółć\n")
    (my/spell--dictionary-merge legacy target)
    (should (equal (my/spell-test--read legacy) "personal_ws-1.1 pl_PL 0 utf-8\nzażółć\n"))))

(ert-deftest my/spell-test-gitattributes-once ()
  "The union line is written once, also into an existing file."
  (my/spell-test--with-folder
    (let ((attributes (expand-file-name ".gitattributes" (file-name-directory target))))
      (my/spell-test--write attributes "*.org diff")
      (my/spell--dictionary-gitattributes target)
      (my/spell--dictionary-gitattributes target)
      (should (equal (my/spell-test--read attributes)
                     "*.org diff\nhunspell_personal merge=union\n")))))

;; ============================================================
;; IMPORT AT START-UP
;; ============================================================

(ert-deftest my/spell-test-prepare-first-machine ()
  "The first machine copies ~/.hunspell_personal and reports it."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "zażółć\n")
    (should (my/spell--dictionary-prepare))
    (should (equal (my/spell-test--read target) "zażółć\n"))
    (should (file-exists-p (expand-file-name ".gitattributes" (file-name-directory target))))
    (should (member legacy (plist-get (my/spell--state-read) :imported)))))

(ert-deftest my/spell-test-prepare-once-per-machine ()
  "The old file is read once; a word removed later does not come back."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "zażółć\nbląd\n")
    (my/spell--dictionary-prepare)
    (my/spell-test--write target "zażółć\n")
    (should (null (my/spell--dictionary-prepare)))
    (should (equal (my/spell-test--read target) "zażółć\n"))))

(ert-deftest my/spell-test-prepare-second-machine ()
  "A second machine adds its own words to the file the first one pushed."
  (my/spell-test--with-folder
    (my/spell-test--write target "zażółć\nDenote\n")
    (my/spell-test--write legacy "Denote\nMyPKS\n")
    (my/spell--dictionary-prepare)
    (should (equal (my/spell-test--read target) "zażółć\nDenote\nMyPKS\n"))))

(ert-deftest my/spell-test-prepare-follows-a-move ()
  "After the file moves, the words of the one used before come along."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (my/spell--dictionary-prepare)
    (let ((my/spell-personal-dictionary (expand-file-name "moved/words" dir)))
      (my/spell--dictionary-prepare)
      (should (equal (my/spell-test--read my/spell-personal-dictionary) "alfa\n"))
      (should (equal (plist-get (my/spell--state-read) :dictionary)
                     (expand-file-name "moved/words" dir))))))

(ert-deftest my/spell-test-prepare-empty-start ()
  "With nothing to bring in, an empty dictionary is created, silently."
  (my/spell-test--with-folder
    (should (null (my/spell--dictionary-prepare)))
    (should (equal (my/spell-test--read target) ""))))

;; ============================================================
;; A FILE CHANGED ON DISK
;; ============================================================

(defmacro my/spell-test--with-fake-hunspell (&rest body)
  "Run BODY with a live process as `ispell-process' and recorded calls.
`sent' collects strings sent to Hunspell, `killed' whether it was stopped."
  (declare (indent 0))
  `(let ((sent nil) (killed nil)
         (ispell-process (start-process "fake-hunspell" nil "cat")))
     (unwind-protect
         (cl-letf (((symbol-function 'ispell-send-string)
                    (lambda (s) (push s sent)))
                   ((symbol-function 'ispell-kill-ispell)
                    (lambda (&rest _) (setq killed t))))
           ,@body)
       (delete-process ispell-process))))

(ert-deftest my/spell-test-sync-new-word ()
  "A word added on disk is accepted for the session, without a restart."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (let ((ispell-personal-dictionary target)
          (my/spell--dictionary-known (my/spell--dictionary-table target)))
      (my/spell-test--with-fake-hunspell
        (my/spell-test--write target "alfa\nbeta\n")
        (my/spell--dictionary-sync)
        (should (equal sent '("@beta\n")))
        (should-not killed)))))

(ert-deftest my/spell-test-sync-removed-word ()
  "A word removed on disk stops Hunspell, which rereads the file later."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\nbeta\n")
    (let ((ispell-personal-dictionary target)
          (my/spell--dictionary-known (my/spell--dictionary-table target)))
      (my/spell-test--with-fake-hunspell
        (my/spell-test--write target "alfa\n")
        (my/spell--dictionary-sync)
        (should killed)))))

(ert-deftest my/spell-test-sync-forbidden-word ()
  "A forbidden word cannot be sent with @: Hunspell is stopped instead."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (let ((ispell-personal-dictionary target)
          (my/spell--dictionary-known (my/spell--dictionary-table target)))
      (my/spell-test--with-fake-hunspell
        (my/spell-test--write target "alfa\n*zle\n")
        (my/spell--dictionary-sync)
        (should killed)
        (should (null sent))))))

(ert-deftest my/spell-test-sync-without-hunspell ()
  "With no Hunspell running, a change is only remembered."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (let ((ispell-personal-dictionary target)
          (ispell-process nil)
          (my/spell--dictionary-known (my/spell--dictionary-table target)))
      (my/spell-test--write target "alfa\nbeta\n")
      (my/spell--dictionary-sync)
      (should (gethash "beta" my/spell--dictionary-known)))))

;; ============================================================
;; SETUP AFTER THE START-UP PULL
;; ============================================================
;; Until 2026-10-22 the setup stopped a running Hunspell at every start
;; ("Ispell process killed" in *Messages*, then started again): the
;; desktop starts it before the pull is done, with the same file.

(ert-deftest my/spell-test-setup-keeps-hunspell-on-the-same-file ()
  "Same file, nothing imported: Hunspell runs on; a pulled word is passed."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (my/spell--dictionary-prepare)
    (let ((ispell-personal-dictionary target)
          (my/spell--dictionary-known (my/spell--dictionary-table target)))
      (my/spell-test--with-fake-hunspell
        (my/spell-test--write target "alfa\nbeta\n")
        (my/spell--dictionary-setup)
        (should-not killed)
        (should (equal sent '("@beta\n")))))))

(ert-deftest my/spell-test-setup-restarts-after-import ()
  "Words brought in from an old file: Hunspell starts again."
  (my/spell-test--with-folder
    (my/spell-test--write legacy "zażółć\n")
    (let ((ispell-personal-dictionary target)
          (my/spell--dictionary-known (make-hash-table :test #'equal)))
      (my/spell-test--with-fake-hunspell
        (my/spell--dictionary-setup)
        (should killed)))))

(ert-deftest my/spell-test-setup-restarts-on-another-file ()
  "Hunspell started with another file: it starts again."
  (my/spell-test--with-folder
    (my/spell-test--write target "alfa\n")
    (my/spell--dictionary-prepare)
    (let ((ispell-personal-dictionary (expand-file-name "other" dir))
          (my/spell--dictionary-known (make-hash-table :test #'equal)))
      (my/spell-test--with-fake-hunspell
        (my/spell--dictionary-setup)
        (should killed)))))

(provide 'test-spelling-dictionary)
;;; test-spelling-dictionary.el ends here
