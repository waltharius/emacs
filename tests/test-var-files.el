;;; test-var-files.el --- ERT tests for the files Emacs writes, out of ~/.emacs.d -*- lexical-binding: t; -*-

;;; Commentary:

;; `my/var--setup' (00-core.el): no-littering loaded with its folders in
;; the settings folder, the old files in ~/.emacs.d moved to var/ and
;; etc/, a file whose new place is taken left where it is, var/ left out
;; of git by the settings folder's .gitignore.
;;
;; The move runs while 00-core.el loads, so the checks run in a fresh
;; `emacs -Q --batch' with its own HOME and ~/.emacs.d holding old files;
;; each prints PASS or FAIL.  no-littering and compat are taken from the
;; packages installed for this user (or from `load-path'); without them
;; the checks of package files are skipped and only the files this
;; configuration names itself are checked.  From the repository root:
;;
;;   emacs -Q --batch -l tests/test-var-files.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'package)
(require 'seq)

(defconst my/var-test--repo
  (expand-file-name
   ".." (file-name-directory (or load-file-name buffer-file-name))))

(defconst my/var-test--old-files
  '(("ed/recentf" . "(setq recentf-list nil)")
    ("ed/saveplace" . "place in use")
    ("ed/places" . "stale place")
    ("ed/history" . "old history")
    ("ed/.org-id-locations" . "ids")
    ("ed/transient/levels.el" . "levels")
    ("ed/persist/org-drill-sm5-optimal-factor-matrix" . "drill")
    ("ed/undo-fu-session/abc" . "undo")
    ("ed/backups/!home!x!file.txt.~1~" . "backup")
    ("ed/notes-root.eld" . "(:current \"~/notes/\")")
    ("ed/keys" . "keylog")
    (".emacs.keyfreq" . "keyfreq")
    ;; Taken already: the old history stays where it is.
    ("settings/hosts/testhost/var/savehist.el" . "new history"))
  "Files written before the start, relative to the test's HOME.")

(defconst my/var-test--checks
  "(defun read-file (f) (with-temp-buffer (insert-file-contents f) (buffer-string)))
(defun home (f) (expand-file-name f (getenv \"HOME\")))
(defun var (f) (home (concat \"settings/hosts/testhost/var/\" f)))
(check \"var/ is in hosts/<host>/\" (equal my/var-directory (var \"\")))
(check \"etc/ is at the root of the settings folder\" (equal my/etc-directory (home \"settings/etc/\")))
(check \"own file moved: undo history\" (and (file-exists-p (var \"undo-fu-session/abc\")) (not (file-exists-p (home \"ed/undo-fu-session\")))))
(check \"own file moved: backups, and the backup folder points there\" (and (file-exists-p (var \"backups/!home!x!file.txt.~1~\")) (equal my-emacs-backups (var \"backups/\"))))
(check \"own file moved: notes root\" (and (equal my/notes-root-state-file (var \"notes-root.eld\")) (not (file-exists-p (home \"ed/notes-root.eld\")))))
(check \"own file moved: keylog of 14-typing-analytics.el\" (and (file-exists-p (var \"keys\")) (not (file-exists-p (home \"ed/keys\")))))
(check \".gitignore leaves var/ out\" (string-match-p \"^/hosts/\\\\*/var/$\" (read-file (home \"settings/.gitignore\"))))
(check \".gitignore line not added twice\" (null (my/var--ignore-in-git)))
(if (not (featurep 'no-littering))
    (princ \"SKIP no-littering not available: package files not checked\\n\")
  (check \"recentf moved, and recentf reads it there\" (and (string-match-p \"recentf-list\" (read-file (var \"recentf-save.el\"))) (equal recentf-save-file (var \"recentf-save.el\"))))
  (check \"saveplace moved, places left: its new place was taken\" (and (equal (read-file (var \"save-place.el\")) \"place in use\") (file-exists-p (home \"ed/places\"))))
  (check \"history left where it was, the new one untouched\" (and (equal (read-file (home \"ed/history\")) \"old history\") (equal (read-file (var \"savehist.el\")) \"new history\")))
  (check \"Org ids moved into a new subfolder\" (file-exists-p (var \"org/id-locations.el\")))
  (check \"menu levels moved to etc/\" (equal (read-file (home \"settings/etc/transient/levels.el\")) \"levels\"))
  (check \"drill data moved, per machine\" (file-exists-p (var \"persist/org-drill-sm5-optimal-factor-matrix\")))
  (check \"~/.emacs.keyfreq moved\" (and (file-exists-p (var \"keyfreq.el\")) (not (file-exists-p (home \".emacs.keyfreq\")))))
  (let ((again (my/var--move-old-files)))
    (check \"second start: nothing moved, the two taken places reported again\"
           (and (null (nth 0 again)) (= (length (nth 1 again)) 2) (null (nth 2 again))))))
"
  "The checks, run in the child Emacs after 00-core.el.")

(defun my/var-test--package-directories ()
  "Return the folders of no-littering and compat, or nil when one is missing."
  (package-initialize)
  (let ((dirs (mapcar (lambda (feature)
                        (when-let* ((file (locate-library (symbol-name feature))))
                          (file-name-directory file)))
                      '(no-littering compat))))
    (unless (memq nil dirs) dirs)))

(defun my/var-test--run ()
  "Write the old files, run the checks in a child Emacs; return its output."
  (let* ((root (make-temp-file "mypks-var-" t))
         (emacs-dir (expand-file-name "ed/" root))
         (script (expand-file-name "checks.el" root))
         (packages (my/var-test--package-directories))
         ;; The child starts in the temporary folder.  Emacs keeps the
         ;; current folder as "~/.emacs.d/" when it is under HOME, and
         ;; with HOME changed below that "~" would mean the temporary
         ;; HOME, where no .emacs.d exists: "Setting current directory".
         (default-directory (file-name-as-directory root))
         (process-environment
          (append (list (concat "HOME=" root)
                        (concat "MYPKS_DIR=" (expand-file-name "settings" root))
                        "MYPKS_HOST=testhost")
                  process-environment)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "modules/" emacs-dir) t)
          (pcase-dolist (`(,file . ,content) my/var-test--old-files)
            (let ((path (expand-file-name file root)))
              (make-directory (file-name-directory path) t)
              (with-temp-file path (insert content))))
          (with-temp-file script
            (insert "(defun check (n ok) (princ (format \"%s %s\\n\" (if ok \"PASS\" \"FAIL\") n)))\n"
                    my/var-test--checks))
          (with-temp-buffer
            (apply #'call-process (expand-file-name invocation-name invocation-directory)
                   nil t nil "-Q" "--batch"
                   (append
                    (mapcan (lambda (dir) (list "-L" dir)) packages)
                    ;; A test installs nothing: no-littering is on
                    ;; `load-path' or absent.
                    (list "--eval" "(setq use-package-ensure-function 'ignore)"
                          "--eval" (format "(setq user-emacs-directory %S)" emacs-dir)
                          "-l" (expand-file-name "modules/00-core.el" my/var-test--repo)
                          "-l" script)))
            (buffer-string)))
      (delete-directory root t))))

(defun my/var-test--count (string regexp)
  "Count the matches of REGEXP in STRING."
  (with-temp-buffer
    (insert string)
    (how-many regexp (point-min) (point-max))))

(ert-deftest my/var-test-all ()
  "Every check passes, and all of them ran."
  (let* ((output (my/var-test--run))
         (passed (my/var-test--count output "^PASS "))
         (skipped (string-match-p "^SKIP " output))
         (failed (seq-filter (lambda (l) (string-prefix-p "FAIL " l))
                             (split-string output "\n"))))
    (should (null failed))
    (should (= passed (if skipped 8 16)))))

(provide 'test-var-files)
;;; test-var-files.el ends here
