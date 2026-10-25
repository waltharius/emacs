;;; test-auto-commit.el --- ERT tests for the background git of 207-git -*- lexical-binding: t; -*-

;; Tests: 207-git

;;; Commentary:
;; The automatic commits of 207-git.el against real repositories: a bare
;; "server" and two clones in a temporary folder, one standing for this
;; machine, the other for the second machine.  No network, no Magit, no
;; rest of the configuration:
;;
;;   emacs -Q --batch -l tests/test-auto-commit.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; Covered: the start-up pull in the background and what waits for it;
;; the commit cycle in the background (add, commit, pull, push), its
;; results when the server is away or the same lines changed on both
;; machines; the blocking form used on the way out; one cycle at a time;
;; an error inside the chain.  Needs git on PATH.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ============================================================
;; STAND-INS FOR 000-core.el
;; ============================================================

(defvar my-notes-dir nil)

(unless (featurep '000-core)
  (defun my/settings-apply-on-set (function)
    "Stand-in: store the value; call FUNCTION outside of loading."
    (lambda (symbol value)
      (set-default-toplevel-value symbol value)
      (when (and after-init-time (not load-file-name) (fboundp function))
        (funcall function)))))

(require 'use-package)
(setq use-package-always-ensure nil
      use-package-ensure-function #'ignore)

(load (expand-file-name "../modules/200-foundation/207-git.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

;; The idle timer is not wanted while the tests run.
(when (timerp my/auto-commit--idle-timer)
  (cancel-timer my/auto-commit--idle-timer))

;; ============================================================
;; FIXTURE
;; ============================================================

(defun my/ac-test--git (dir &rest args)
  "Run git ARGS in DIR quietly; return its exit status."
  (let ((default-directory (file-name-as-directory dir)))
    (apply #'call-process "git" nil nil nil args)))

(defun my/ac-test--git-lines (dir &rest args)
  "Run git ARGS in DIR; return its output lines."
  (let ((default-directory (file-name-as-directory dir)))
    (apply #'process-lines "git" args)))

(defun my/ac-test--write (file text)
  "Write TEXT to FILE."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file file (insert text))))

(defun my/ac-test--clone (root name)
  "Clone ROOT/server.git as ROOT/NAME with a test identity; return its folder."
  (let ((dir (expand-file-name (concat name "/") root)))
    (my/ac-test--git root "clone" "-q" "server.git" name)
    (my/ac-test--git dir "config" "user.email" "test@example.invalid")
    (my/ac-test--git dir "config" "user.name" "Test")
    dir))

(defmacro my/ac-test--with-repos (&rest body)
  "Run BODY with a server and two clones; `here', `there', `server' bound.
`here' is this machine's notes folder, `there' the other machine's."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-git-" t)))
          (server (expand-file-name "server.git/" root))
          (here nil) (there nil)
          (my/auto-commit-repository-sources
           (list (lambda () (list here))))
          (my/auto-commit-pull t)
          (my/auto-commit-push t)
          (my/auto-commit-no-push-directories nil)
          (my/auto-commit-config-enabled nil)
          (my/auto-commit--startup-pull-running nil)
          (my/auto-commit--startup-pull-waiting nil)
          (my/auto-commit--cycle-running nil)
          (my/auto-commit--conflicts nil)
          (my/auto-commit--reported nil)
          (warning-minimum-log-level :emergency)
          (inhibit-message t))
     (unwind-protect
         (progn
           (my/ac-test--git root "init" "-q" "--bare" "-b" "main" "server.git")
           (setq here (my/ac-test--clone root "here"))
           (my/ac-test--write (expand-file-name "a.org" here) "line one\n")
           (my/ac-test--git here "add" "-A")
           (my/ac-test--git here "commit" "-qm" "init")
           (my/ac-test--git here "push" "-q" "-u" "origin" "HEAD")
           (setq there (my/ac-test--clone root "there"))
           (setq my-notes-dir here)
           ,@body)
       (delete-directory root t))))

(defun my/ac-test--wait (&optional seconds)
  "Serve processes until no background git runs, at most SECONDS (10)."
  (let ((deadline (+ (float-time) (or seconds 10))))
    (while (and (my/auto-commit--busy-in-background-p)
                (< (float-time) deadline))
      (accept-process-output nil 0.05))))

(defun my/ac-test--other-machine-commits (there file text)
  "On THERE, pull, write TEXT to FILE, commit and push."
  (my/ac-test--git there "pull" "-q")
  (my/ac-test--write (expand-file-name file there) text)
  (my/ac-test--git there "add" "-A")
  (my/ac-test--git there "commit" "-qm" "other machine")
  (my/ac-test--git there "push" "-q"))

(defun my/ac-test--server-subject (server)
  "Return the subject of the newest commit on SERVER."
  (let ((default-directory server))
    (car (process-lines "git" "log" "-1" "--format=%s"))))

(defun my/ac-test--cycle ()
  "Run one background cycle, wait for it; return its descriptions."
  (let ((result 'none))
    (my/auto-commit--cycle (lambda (r) (setq result r)) t)
    (my/ac-test--wait)
    result))

;; ============================================================
;; COMMIT MESSAGES WRITTEN BY HAND
;; ============================================================

(ert-deftest my/ac-test-commit-message-wraps-at-72 ()
  "Once Magit is loaded, a commit message buffer wraps at 72 columns:
the function is on `git-commit-setup-hook' and sets `fill-column' there,
for that buffer only.  (Until 2026-10-24 through Magit's
`git-commit-fill-column', which Magit 4 removed.)"
  ;; Skipped only when Magit is not installed.  Installed but failing to
  ;; load is a failure with the load error, not a skip: until 2026-10-25
  ;; `(require 'magit nil t)' made the two look alike, and on the
  ;; owner's machine the test was skipped with Magit installed.
  (unless (locate-library "magit")
    (ert-skip "Magit is not installed"))
  ;; An error while Magit loads or sets a buffer up is reported with
  ;; the versions package.el activated: on the owner's machine (2026-10-25)
  ;; it was (void-function transient--set-layout), Magit running with a
  ;; transient older than the one it was built for, and the plain error
  ;; did not say which transient that was.
  (condition-case err
      (progn
        (require 'magit)
        (should (memq #'my/git-commit-fill-column git-commit-setup-hook))
        (let ((default fill-column))
          (with-temp-buffer
            (run-hooks 'git-commit-setup-hook)
            (should (= fill-column 72))
            (should (local-variable-p 'fill-column)))
          (should (= fill-column default))))
    ((error void-function)
     (ert-fail (list err (my/ac-test--magit-packages))))))

(defun my/ac-test--magit-packages ()
  "Describe the packages Magit runs on: what is installed, what is loaded.
For each, the versions installed (package.el's newest first, the one it
activates) and the folder of the first; for transient also the file
loaded and its version.  A MELPA build is numbered by date, so an old
one (transient-20250301.1200) counts as newer than any GNU ELPA release
(transient-0.13.8): package.el keeps activating it and does not upgrade
it for a Magit that asks for transient 0.13."
  (append
   (mapcar (lambda (name)
             (let ((descs (alist-get name package-alist)))
               (list name
                     (mapcar (lambda (d) (package-version-join (package-desc-version d)))
                             descs)
                     (and descs (package-desc-dir (car descs))))))
           '(transient magit magit-section with-editor compat cond-let llama))
   (list (list 'transient-loaded-from (locate-library "transient")
               'transient-version (bound-and-true-p transient-version)
               'transient-built-in (alist-get 'transient package--builtin-versions)))))

;; ============================================================
;; START-UP PULL
;; ============================================================

(ert-deftest my/ac-test-startup-pull-in-background ()
  "The pull returns at once, brings the other machine's work, then runs waiters."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "b.org" "from there\n")
    (let ((called nil) (hook-lines 'none)
          (my/auto-commit-pull-done-hook nil))
      (add-hook 'my/auto-commit-pull-done-hook (lambda (lines) (setq hook-lines lines)))
      (let ((t0 (float-time)))
        (my/auto-commit--startup-pull)
        (should (< (- (float-time) t0) 1.0)))
      (should my/auto-commit--startup-pull-running)
      (my/auto-commit-after-startup-pull (lambda () (setq called t)))
      (should-not called)
      (my/ac-test--wait)
      (should (file-exists-p (expand-file-name "b.org" here)))
      (should called)
      (should (equal hook-lines '("here: updated from the server"))))))

(ert-deftest my/ac-test-after-startup-pull-without-pull ()
  "With no pull running, the function runs at once."
  (let ((my/auto-commit--startup-pull-running nil) (called nil))
    (my/auto-commit-after-startup-pull (lambda () (setq called t)))
    (should called)))

(ert-deftest my/ac-test-startup-pull-conflict ()
  "The same line changed on both machines: reported, rebase undone, file kept."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "a.org" "there's version\n")
    (my/ac-test--write (expand-file-name "a.org" here) "here's version\n")
    (my/ac-test--git here "commit" "-qam" "here")
    (let ((lines 'none) (my/auto-commit-pull-done-hook nil))
      (add-hook 'my/auto-commit-pull-done-hook (lambda (l) (setq lines l)))
      (my/auto-commit--startup-pull)
      (my/ac-test--wait)
      (should (equal lines '("here: CONFLICT, see *Warnings*")))
      (should-not (my/auto-commit--busy-p here))
      (should (equal (with-temp-buffer
                       (insert-file-contents (expand-file-name "a.org" here))
                       (buffer-string))
                     "here's version\n")))))

;; Fixed 2026-10-24 (outside audits): the pull used --autostash, which
;; can write conflict markers into a file and exit 0.
(ert-deftest my/ac-test-startup-pull-with-uncommitted-change ()
  "A change saved but not committed, on a line the other machine changed
too: the start-up pull does not run, the file keeps exactly what was
written here -- no conflict markers -- and the line says why."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "a.org" "there's version\n")
    (my/ac-test--write (expand-file-name "a.org" here) "here, not committed\n")
    (let ((lines 'none) (my/auto-commit-pull-done-hook nil))
      (add-hook 'my/auto-commit-pull-done-hook (lambda (l) (setq lines l)))
      (my/auto-commit--startup-pull)
      (my/ac-test--wait)
      (should (equal lines '("here: changes not committed yet, not pulled"))))
    (should (equal (with-temp-buffer
                     (insert-file-contents (expand-file-name "a.org" here))
                     (buffer-string))
                   "here, not committed\n"))
    (should-not (my/auto-commit--unmerged-p here))
    (should-not (my/ac-test--git-lines here "stash" "list"))))

(ert-deftest my/ac-test-conflict-markers-stop-the-cycle ()
  "Files left with an unresolved conflict -- as `git pull --autostash'
leaves them, exiting 0 -- are neither committed nor pushed; the
repository is reported, with the files named."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "a.org" "there's version\n")
    (my/ac-test--write (expand-file-name "a.org" here) "here, not committed\n")
    (should (= 0 (my/ac-test--git here "pull" "-q" "--rebase" "--autostash")))
    (should (equal (my/auto-commit--unmerged-p here) '("a.org")))
    (let ((head (my/ac-test--git-lines here "rev-parse" "HEAD"))
          (on-server (my/ac-test--server-subject server)))
      (should-not (my/ac-test--cycle))
      (should (equal (my/ac-test--git-lines here "rev-parse" "HEAD") head))
      (should (equal (my/ac-test--server-subject server) on-server)))
    (should (my/auto-commit--busy-p here))
    (should (equal (my/auto-commit-pending here) "files hold conflict markers"))
    (should (string-search "a.org" (my/auto-commit--advice here "files hold conflict markers")))))

(ert-deftest my/ac-test-failed-add-stops-the-cycle ()
  "When `git add' fails -- a lock left by an interrupted git -- the cycle
stops there with an error: nothing is committed, pulled or pushed."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "b.org" "from there\n")
    (my/ac-test--write (expand-file-name "c.org" here) "new here\n")
    (my/ac-test--write (expand-file-name ".git/index.lock" here) "")
    (let ((result (my/ac-test--cycle)))
      (should (equal (length result) 1))
      (should (string-match-p "\\`here: ERROR git add failed" (car result))))
    (should-not (file-exists-p (expand-file-name "b.org" here)))
    (should (equal (my/ac-test--server-subject server) "other machine"))))

;; A repository git refuses: every question fails.  A damaged .git/HEAD
;; stands in for `detected dubious ownership', which needs another user.
(defun my/ac-test--break-repository (dir)
  "Make git refuse DIR as a repository."
  (my/ac-test--write (expand-file-name ".git/HEAD" dir) "not a reference\n"))

(ert-deftest my/ac-test-unreadable-repository-reported ()
  "A repository git cannot read is reported with git's message, not
taken for one with nothing to do."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "c.org" here) "new here\n")
    (my/ac-test--break-repository here)
    (let ((reason (my/auto-commit-pending here)))
      (should (stringp reason))
      (should (string-prefix-p "git cannot read the repository: " reason))
      (should (string-match-p "not a git repository" reason))
      (should (string-search "safe.directory" (my/auto-commit--advice here reason))))))

(ert-deftest my/ac-test-unreadable-repository-cycle-fails-loudly ()
  "The cycle on a repository git cannot read ends in an error line, not
in silence; `git status' failing counts as changes, never as none."
  (my/ac-test--with-repos
    (my/ac-test--break-repository here)
    (should (my/auto-commit--dirty-p here))
    (let ((result (my/ac-test--cycle)))
      (should (equal (length result) 1))
      (should (string-match-p "\\`here: ERROR" (car result))))))

(ert-deftest my/ac-test-readable-repository-no-reason ()
  "A healthy repository with everything pushed gives no reason at all."
  (my/ac-test--with-repos
    (should-not (my/auto-commit--unreadable here))
    (should-not (my/auto-commit--dirty-p here))
    (should-not (my/auto-commit-pending here))))

;; ============================================================
;; THE COMMIT CYCLE
;; ============================================================

(ert-deftest my/ac-test-cycle-commits-and-pushes ()
  "A new note -- a Polish title with an apostrophe and a semicolon -- reaches the server."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "20261019T120000--zażółć it's; a test__pks.org" here)
                       "x\n")
    (should (equal (my/ac-test--cycle) '("here: committed, pushed")))
    (should (string-prefix-p "Auto-commit:" (my/ac-test--server-subject server)))
    (should (null (my/auto-commit-pending here)))
    (let ((default-directory server))
      (should (string-match-p "zażółć it's; a test"
                              (string-join (process-lines "git" "log" "-1" "--format=%B")
                                           "\n"))))))

(ert-deftest my/ac-test-cycle-pulls-before-pushing ()
  "Work pushed by the other machine meanwhile is pulled, then ours pushed."
  (my/ac-test--with-repos
    (my/ac-test--other-machine-commits there "b.org" "from there\n")
    (my/ac-test--write (expand-file-name "c.org" here) "c\n")
    (should (equal (my/ac-test--cycle) '("here: committed, pulled, pushed")))
    (should (file-exists-p (expand-file-name "b.org" here)))))

(ert-deftest my/ac-test-cycle-offline ()
  "Without the server: committed here, not pushed, reported as pending."
  (my/ac-test--with-repos
    (my/ac-test--git here "remote" "set-url" "origin"
                     (expand-file-name "missing.git" (file-name-directory
                                                      (directory-file-name here))))
    (my/ac-test--write (expand-file-name "e.org" here) "e\n")
    (should (equal (my/ac-test--cycle) '("here: committed, server unreachable")))
    (should (equal (my/auto-commit-pending here) "commits not pushed"))))

(ert-deftest my/ac-test-cycle-nothing-to-do ()
  "A clean repository level with its server gives no description."
  (my/ac-test--with-repos
    (should (null (my/ac-test--cycle)))))

(ert-deftest my/ac-test-blocking-form ()
  "`my/auto-commit-all' waits for git and returns the descriptions."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "d.org" here) "d\n")
    (should (equal (my/auto-commit-all) '("here: committed, pushed")))
    (should-not my/auto-commit--cycle-running)))

(ert-deftest my/ac-test-commit-waits-for-startup-pull ()
  "A blocking commit started during the start-up pull runs after it.
The note is written once the pull runs: a tree with changes not
committed is not pulled at all (since 2026-10-24)."
  (my/ac-test--with-repos
    (my/auto-commit--startup-pull)
    (should my/auto-commit--startup-pull-running)
    (my/ac-test--write (expand-file-name "d.org" here) "d\n")
    (should (equal (my/auto-commit-all) '("here: committed, pushed")))
    (should-not my/auto-commit--startup-pull-running)))

(ert-deftest my/ac-test-one-cycle-at-a-time ()
  "The idle timer does not start a cycle while one runs."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "f.org" here) "f\n")
    (my/auto-commit--cycle #'ignore t)
    (let ((started 0))
      (cl-letf (((symbol-function 'my/auto-commit--cycle)
                 (lambda (&rest _) (setq started (1+ started)))))
        (my/auto-commit--on-idle))
      (should (= started 0)))
    (my/ac-test--wait)))

(ert-deftest my/ac-test-error-ends-chain-once ()
  "An error inside the chain is reported as ERROR, and the callback runs once."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "g.org" here) "g\n")
    (let ((results nil))
      (cl-letf (((symbol-function 'my/auto-commit--message)
                 (lambda (_dir) (error "boom"))))
        (my/auto-commit-repository-async here (lambda (r) (push r results)))
        (let ((deadline (+ (float-time) 10)))
          (while (and (null results) (< (float-time) deadline))
            (accept-process-output nil 0.05)))
        (accept-process-output nil 0.3))
      (should (= (length results) 1))
      (should (string-match-p "ERROR boom" (car results))))))

;; ============================================================
;; THE WAY OUT
;; ============================================================

(ert-deftest my/ac-test-exit-commit-once ()
  "The exit commit pushes, waiting for git, and runs once per session."
  (my/ac-test--with-repos
    (let ((my/auto-commit-done nil))
      (my/ac-test--write (expand-file-name "h.org" here) "h\n")
      (should (equal (my/auto-commit-exit-commit) '("here: committed, pushed")))
      (my/ac-test--write (expand-file-name "i.org" here) "i\n")
      (should (null (my/auto-commit-exit-commit)))
      (should (my/auto-commit--dirty-p here)))))

(ert-deftest my/ac-test-staying-commits-again ()
  "Answering no to the question keeps Emacs open, and the next quit commits again."
  (my/ac-test--with-repos
    (my/ac-test--git here "remote" "set-url" "origin"
                     (expand-file-name "missing.git" (file-name-directory
                                                      (directory-file-name here))))
    (let ((my/auto-commit-done nil)
          (my/auto-commit-confirm-exit t)
          (noninteractive nil))
      (my/ac-test--write (expand-file-name "j.org" here) "j\n")
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (should-not (my/auto-commit--confirm-exit)))
      (should-not my/auto-commit-done)
      (my/ac-test--write (expand-file-name "k.org" here) "k\n")
      (should (equal (my/auto-commit-exit-commit)
                     '("here: committed, server unreachable"))))))

(ert-deftest my/ac-test-last-client-frame-only-in-daemon ()
  "Outside a daemon, deleting a frame starts no cycle."
  (let ((started nil))
    (cl-letf (((symbol-function 'my/auto-commit--cycle)
               (lambda (&rest _) (setq started t)))
              ((symbol-function 'daemonp) (lambda () nil)))
      (my/auto-commit--on-last-client-frame (selected-frame)))
    (should-not started)))

;; ============================================================
;; WHAT IS COMMITTED AND WHERE IT GOES (SAFETY.org 3.1)
;; ============================================================

(defun my/ac-test--refs (repo)
  "Return the branches REPO (a bare repository) holds."
  (let ((default-directory (file-name-as-directory repo)))
    (process-lines "git" "for-each-ref" "--format=%(refname)" "refs/heads")))

(ert-deftest my/ac-test-config-repository-off-by-default ()
  "This repository is not committed automatically unless asked for."
  (should-not (eval (car (get 'my/auto-commit-config-enabled 'standard-value)) t)))

(ert-deftest my/ac-test-directories-are-the-sources ()
  "Only the folders the sources name are committed; the configuration
repository only when turned on."
  (my/ac-test--with-repos
    (should (equal (my/auto-commit-directories) (list here)))
    (let ((my/auto-commit-config-enabled t))
      (should (equal (my/auto-commit-directories)
                     (list here (expand-file-name user-emacs-directory)))))))

(ert-deftest my/ac-test-push-only-to-upstream-remotes-unchanged ()
  "With a second remote, the push goes to the upstream only, and the
remotes are the same afterwards."
  (my/ac-test--with-repos
    (let ((backup (expand-file-name "backup.git" (file-name-directory (directory-file-name here)))))
      (my/ac-test--git (file-name-directory (directory-file-name here))
                       "init" "-q" "--bare" "-b" "main" "backup.git")
      (my/ac-test--git here "remote" "add" "backup" backup)
      (let ((remotes (let ((default-directory here)) (process-lines "git" "remote" "-v"))))
        (my/ac-test--write (expand-file-name "f.org" here) "f\n")
        (should (equal (my/ac-test--cycle) '("here: committed, pushed")))
        (should (null (my/ac-test--refs backup)))
        (should (equal (let ((default-directory here)) (process-lines "git" "remote" "-v"))
                       remotes))))))

(ert-deftest my/ac-test-no-push-directory-committed-not-pushed ()
  "A folder kept from pushing is committed here; the server is untouched."
  (my/ac-test--with-repos
    (let ((my/auto-commit-no-push-directories (list here))
          (before (my/ac-test--server-subject server)))
      (my/ac-test--write (expand-file-name "g.org" here) "g\n")
      (should (equal (my/ac-test--cycle) '("here: committed")))
      (should (equal (my/ac-test--server-subject server) before)))))

(ert-deftest my/ac-test-push-off-committed-not-pushed ()
  "Pushing turned off: committed here, nothing on the server."
  (my/ac-test--with-repos
    (let ((my/auto-commit-push nil)
          (before (my/ac-test--server-subject server)))
      (my/ac-test--write (expand-file-name "h.org" here) "h\n")
      (should (equal (my/ac-test--cycle) '("here: committed")))
      (should (equal (my/ac-test--server-subject server) before)))))

(ert-deftest my/ac-test-folder-without-repository-left-alone ()
  "A source folder that is no git repository is skipped: no repository
is created, nothing is run."
  (my/ac-test--with-repos
    (let* ((plain (file-name-as-directory
                   (expand-file-name "plain" (file-name-directory (directory-file-name here)))))
           (my/auto-commit-repository-sources (list (lambda () (list plain)))))
      (make-directory plain t)
      (my/ac-test--write (expand-file-name "i.org" plain) "i\n")
      (should (null (my/ac-test--cycle)))
      (should-not (file-exists-p (expand-file-name ".git" plain))))))

(ert-deftest my/ac-test-rebase-in-progress-left-alone ()
  "A repository in the middle of a rebase is not committed."
  (my/ac-test--with-repos
    (make-directory (expand-file-name ".git/rebase-merge" here) t)
    (my/ac-test--write (expand-file-name "j.org" here) "j\n")
    (should (null (my/ac-test--cycle)))
    (should (my/auto-commit--dirty-p here))))

;; ============================================================
;; A COMMIT MESSAGE BEING WRITTEN
;; ============================================================
;; 2026-10-22: with C-c v c working, git waits for the message in a
;; buffer of with-editor.  A commit made meanwhile moves HEAD, and the
;; waiting commit then fails; quitting with the buffer out of sight
;; asked about active processes and other clients.

(defvar with-editor-mode nil
  "Stand-in for with-editor's buffer-local mode variable (no Magit here).")
(make-variable-buffer-local 'with-editor-mode)

(defmacro my/ac-test--with-message-buffer (dir &rest body)
  "Run BODY with a commit message buffer of with-editor open for DIR."
  (declare (indent 1))
  `(let ((buffer (generate-new-buffer "COMMIT_EDITMSG")))
     (unwind-protect
         (progn
           (with-current-buffer buffer
             (setq buffer-file-name (expand-file-name ".git/COMMIT_EDITMSG" ,dir))
             (setq with-editor-mode t))
           ,@body)
       (with-current-buffer buffer (set-buffer-modified-p nil))
       (kill-buffer buffer))))

(ert-deftest my/ac-test-open-message-skips-repository ()
  "While a commit message is written for a repository, no automatic
commit is made there; once it is closed, the next cycle commits."
  (my/ac-test--with-repos
    (my/ac-test--write (expand-file-name "m.org" here) "m\n")
    (my/ac-test--with-message-buffer here
      (should (my/auto-commit--busy-p here))
      (should (null (my/ac-test--cycle)))
      (should (my/auto-commit--dirty-p here)))
    (should-not (my/auto-commit--busy-p here))
    (should (equal (my/ac-test--cycle) '("here: committed, pushed")))))

(ert-deftest my/ac-test-open-message-elsewhere-ignored ()
  "A message buffer of another repository does not hold this one back."
  (my/ac-test--with-repos
    (my/ac-test--with-message-buffer there
      (should-not (my/auto-commit--busy-p here)))))

(ert-deftest my/ac-test-quit-asks-about-open-message ()
  "Quitting with a message open asks first; no stops the quit."
  (my/ac-test--with-repos
    (my/ac-test--with-message-buffer here
      (let ((asked 0) (noninteractive nil))
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (cl-incf asked) nil))
                  ((symbol-function 'pop-to-buffer) #'ignore))
          (should-error (my/auto-commit--message-before-quit) :type 'user-error))
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (cl-incf asked) t)))
          (should-not (my/auto-commit--message-before-quit)))
        (should (= asked 2))))
    (let ((noninteractive nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "Asked"))))
        (should-not (my/auto-commit--message-before-quit))))))

(provide 'test-auto-commit)
;;; test-auto-commit.el ends here
