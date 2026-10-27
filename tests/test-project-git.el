;;; test-project-git.el --- ERT tests for the remotes and pulls of 439-project-git -*- lexical-binding: t; -*-

;; Tests: 439-project-git

;;; Commentary:

;; 439-project-git.el creates a writing project's repository, gives it a
;; remote, pushes it, and fast-forwards it when it is behind -- the only
;; module that adds or changes a remote (SAFETY.org 3.1).  The seventh
;; module of TESTING.org, *Every module tested*, part 3.  With real git:
;; projects in a temporary folder (428-writing-projects.el lists them), a
;; bare repository per project standing for the server, a second clone
;; standing for the other machine.  No network.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-project-git.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  Needs git on PATH.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "428-writing-projects" "439-project-git")

;; ============================================================
;; FIXTURE
;; ============================================================

(defun my/pg-test--git (dir &rest args)
  "Run git ARGS in DIR with a test identity; return trimmed output or signal."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (unless (= 0 (apply #'call-process "git" nil t nil
                          "-c" "user.name=Test" "-c" "user.email=test@example.invalid"
                          "-c" "init.defaultBranch=main" args))
        (error "git %S in %s failed: %s" args dir (buffer-string)))
      (string-trim (buffer-string)))))

(defmacro my/pg-test--with-projects (&rest body)
  "Run BODY with an empty projects folder and a server folder.
Binds `root', `projects', `server'.  Commits get a test identity."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-pg-" t)))
          (projects (file-name-as-directory (expand-file-name "projects" root)))
          (server (file-name-as-directory (expand-file-name "server" root)))
          (my/writing-projects-directory projects)
          (my/project-git-remote-format nil)
          (my/project-git-remote-name "origin")
          (my/project-git-branch "main")
          (my/project-git-auto-pull nil)
          (process-environment (append '("GIT_AUTHOR_NAME=Test" "GIT_COMMITTER_NAME=Test"
                                         "GIT_AUTHOR_EMAIL=test@example.invalid"
                                         "GIT_COMMITTER_EMAIL=test@example.invalid")
                                       process-environment))
          (inhibit-message t))
     (make-directory projects t)
     (make-directory server t)
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root f))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/pg-test--project (projects slug &optional text)
  "Make project SLUG in PROJECTS: its folder and hub file.  Return the folder."
  (let ((dir (file-name-as-directory (expand-file-name slug projects))))
    (make-directory dir t)
    (with-temp-file (expand-file-name (concat slug ".org") dir)
      (insert "#+title: " slug "\n\n" (or text "Text.\n")))
    dir))

(defun my/pg-test--bare (server slug)
  "Make the bare repository SERVER/SLUG.git; return the remote format."
  (my/pg-test--git server "init" "--quiet" "--bare" "-b" "main" (concat slug ".git"))
  (concat "file://" (directory-file-name server) "/%s.git"))

(defun my/pg-test--published (projects server slug)
  "Make project SLUG with a server copy and a second clone; return the clone."
  (let ((dir (my/pg-test--project projects slug)))
    (setq my/project-git-remote-format (my/pg-test--bare server slug))
    (my/project-git-init slug t)
    (let ((other (expand-file-name (concat slug "-other") server)))
      (my/pg-test--git server "clone" "--quiet" (format my/project-git-remote-format slug) other)
      (ignore dir)
      other)))

(defun my/pg-test--commit-elsewhere (other file text)
  "On the clone OTHER, write TEXT to FILE, commit and push."
  (with-temp-file (expand-file-name file other) (insert text))
  (my/pg-test--git other "add" "-A")
  (my/pg-test--git other "commit" "--quiet" "-m" "elsewhere")
  (my/pg-test--git other "push" "--quiet"))

;; ============================================================
;; A REPOSITORY FOR A PROJECT
;; ============================================================

(ert-deftest my/pg-test-init-without-server-local-only ()
  "No server configured: a repository on main, a .gitignore, the first
commit -- and no remote."
  (my/pg-test--with-projects
    (let ((dir (my/pg-test--project projects "essay")))
      (my/project-git-init "essay" t)
      (should (equal (my/pg-test--git dir "branch" "--show-current") "main"))
      (should (file-exists-p (expand-file-name ".gitignore" dir)))
      (should (equal (my/pg-test--git dir "log" "--format=%s") "Start project 'essay'"))
      (should (equal (my/pg-test--git dir "remote") "")))))

(ert-deftest my/pg-test-init-keeps-own-gitignore ()
  "A .gitignore already in the project is not replaced."
  (my/pg-test--with-projects
    (let ((dir (my/pg-test--project projects "essay")))
      (with-temp-file (expand-file-name ".gitignore" dir) (insert "mine\n"))
      (my/project-git-init "essay" t)
      (should (equal (with-temp-buffer
                       (insert-file-contents (expand-file-name ".gitignore" dir))
                       (buffer-string))
                     "mine\n")))))

(ert-deftest my/pg-test-init-pushes-to-server ()
  "With a server: the remote is the configured one, the branch tracks it,
and the server has the first commit."
  (my/pg-test--with-projects
    (let ((dir (my/pg-test--project projects "essay")))
      (setq my/project-git-remote-format (my/pg-test--bare server "essay"))
      (my/project-git-init "essay" t)
      (should (equal (my/pg-test--git dir "remote" "get-url" "origin")
                     (format my/project-git-remote-format "essay")))
      (should (equal (my/pg-test--git dir "rev-parse" "--abbrev-ref" "@{u}") "origin/main"))
      (should (equal (my/pg-test--git (expand-file-name "essay.git" server) "log" "--format=%s" "main")
                     "Start project 'essay'")))))

(ert-deftest my/pg-test-set-remote-changes-only-its-remote ()
  "Setting the remote changes the configured remote only; another remote
of the project stays as it was."
  (my/pg-test--with-projects
    (let ((dir (my/pg-test--project projects "essay")))
      (my/project-git-init "essay" t)
      (my/pg-test--git dir "remote" "add" "backup" "file:///elsewhere/backup.git")
      (my/pg-test--git dir "remote" "add" "origin" "file:///old/essay.git")
      (setq my/project-git-remote-format "file:///new/%s.git")
      (my/project-git-set-remote "essay")
      (should (equal (my/pg-test--git dir "remote" "get-url" "origin") "file:///new/essay.git"))
      (should (equal (my/pg-test--git dir "remote" "get-url" "backup") "file:///elsewhere/backup.git")))))

(ert-deftest my/pg-test-set-remote-without-server-refused ()
  "No server configured: setting a remote is refused, the remotes unchanged."
  (my/pg-test--with-projects
    (let ((dir (my/pg-test--project projects "essay")))
      (my/project-git-init "essay" t)
      (my/pg-test--git dir "remote" "add" "origin" "file:///old/essay.git")
      (should-error (my/project-git-set-remote "essay") :type 'user-error)
      (should (equal (my/pg-test--git dir "remote" "get-url" "origin") "file:///old/essay.git")))))

(ert-deftest my/pg-test-git-never-prompts ()
  "Git runs with GIT_TERMINAL_PROMPT=0: a password question fails at once."
  ;; Whatever the environment Emacs started in says (this machine's
  ;; sets it already, which hid a missing setting once).
  (let ((process-environment (cons "GIT_TERMINAL_PROMPT=1"
                                   (seq-remove (lambda (e) (string-prefix-p "GIT_TERMINAL_PROMPT=" e))
                                               process-environment))))
    (should (equal (getenv-internal "GIT_TERMINAL_PROMPT" (my/project-git--env)) "0"))))

;; ============================================================
;; BEHIND THE SERVER
;; ============================================================

(defun my/pg-test--report (dir &optional command)
  "Fetch DIR and report, as the check does; wait for it; return the message.
COMMAND runs instead of the check: a function of DIR, such as
`my/project-git-pull'."
  (let ((said nil))
    (cl-letf (((symbol-function 'message)
               (lambda (f &rest a) (setq said (apply #'format f a)))))
      (if command
          (funcall command dir)
        (my/project-git--fetch-and-report dir :verbose))
      (with-timeout (10 (error "The fetch did not end"))
        (while (seq-some (lambda (p) (string-prefix-p "project-git-fetch" (process-name p)))
                         (process-list))
          (accept-process-output nil 0.05))))
    said))

(ert-deftest my/pg-test-behind-only-warns-by-default ()
  "Auto-pull is off by default.  Behind the server with it off: a
message, nothing pulled."
  (should-not (eval (car (get 'my/project-git-auto-pull 'standard-value)) t))
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay")))
      (my/pg-test--commit-elsewhere other "new.org" "from there\n")
      (should (string-match-p "1 commit(s) behind" (my/pg-test--report dir)))
      (should-not (file-exists-p (expand-file-name "new.org" dir))))))

(ert-deftest my/pg-test-pull-fast-forwards-a-clean-tree ()
  "Auto-pull on, clean tree: fast-forwarded; an open unmodified buffer
shows the new text, a buffer with unsaved edits keeps them."
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay"))
           (my/project-git-auto-pull t)
           ;; Opening the files would check (and pull) by itself; this
           ;; test is about the pull, the next one about the check.
           (my/project-git-check-on-visit nil)
           (hub (expand-file-name "essay.org" dir))
           (side (expand-file-name "side.org" dir)))
      ;; A second file, committed here and pushed, then edited unsaved.
      (with-temp-file side (insert "side\n"))
      (my/pg-test--git dir "add" "-A")
      (my/pg-test--git dir "commit" "--quiet" "-m" "side")
      (my/pg-test--git dir "push" "--quiet")
      (my/pg-test--git other "pull" "--quiet")
      (my/pg-test--commit-elsewhere other "essay.org" "#+title: essay\n\nChanged there.\n")
      (let ((hub-buffer (find-file-noselect hub))
            (side-buffer (find-file-noselect side)))
        (with-current-buffer side-buffer (goto-char (point-max)) (insert "typed"))
        ;; The dirty buffer is not on disk: the tree is still clean.
        (should (string-match-p "pulled 1 commit" (my/pg-test--report dir)))
        (with-current-buffer hub-buffer
          (should (string-match-p "Changed there" (buffer-string))))
        (with-current-buffer side-buffer
          (should (string-match-p "typed" (buffer-string))))))))

(ert-deftest my/pg-test-pull-command-pulls-with-auto-pull-off ()
  "`my/project-git-pull' fast-forwards a clean tree although
`my/project-git-auto-pull' is off.  Until 2026-10-28 the command
let-bound the option around an asynchronous fetch; the sentinel saw the
global nil and only said \"behind, C-c n p G u to pull\"."
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay"))
           (my/project-git-auto-pull nil)
           (my/project-git-check-on-visit nil)
           (hub (expand-file-name "essay.org" dir)))
      (my/pg-test--commit-elsewhere other "essay.org" "#+title: essay\n\nChanged there.\n")
      (should (string-match-p "pulled 1 commit"
                              (my/pg-test--report dir (lambda (d) (my/project-git-pull
                                                                 (file-name-nondirectory
                                                                  (directory-file-name d)))))))
      (should (string-match-p "Changed there"
                              (with-temp-buffer (insert-file-contents hub) (buffer-string))))
      ;; The check afterwards, with the option still off, pulls nothing.
      (my/pg-test--commit-elsewhere other "essay.org" "#+title: essay\n\nAgain.\n")
      (should (string-match-p "1 commit(s) behind" (my/pg-test--report dir))))))

(ert-deftest my/pg-test-opening-a-file-checks ()
  "Opening a file of a project behind its server says so, once in the
check interval, without anything having to be remembered."
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay"))
           (my/project-git-check-on-visit t)
           (my/project-git--checked (make-hash-table :test #'equal))
           (said nil))
      (my/pg-test--commit-elsewhere other "new.org" "from there\n")
      (cl-letf (((symbol-function 'message)
                 (lambda (f &rest a) (setq said (apply #'format f a)))))
        (with-current-buffer (find-file-noselect (expand-file-name "essay.org" dir))
          (my/project-git--maybe-check))
        (with-timeout (10 (error "The fetch did not end"))
          (while (seq-some (lambda (p) (string-prefix-p "project-git-fetch" (process-name p)))
                           (process-list))
            (accept-process-output nil 0.05))))
      (should (string-match-p "1 commit(s) behind" said))
      (should-not (my/project-git--due-p dir)))))

(ert-deftest my/pg-test-pull-refused-on-dirty-tree ()
  "Auto-pull on, uncommitted changes on disk: nothing pulled."
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay"))
           (my/project-git-auto-pull t))
      (my/pg-test--commit-elsewhere other "new.org" "from there\n")
      (with-temp-file (expand-file-name "essay.org" dir) (insert "local change\n"))
      (should (string-match-p "working tree is dirty" (my/pg-test--report dir)))
      (should-not (file-exists-p (expand-file-name "new.org" dir))))))

(ert-deftest my/pg-test-diverged-never-merged ()
  "Commits on both sides: reported as diverged, nothing merged, even
with auto-pull on."
  (my/pg-test--with-projects
    (let* ((other (my/pg-test--published projects server "essay"))
           (dir (my/project-git--directory "essay"))
           (my/project-git-auto-pull t)
           (head nil))
      (my/pg-test--commit-elsewhere other "new.org" "from there\n")
      (with-temp-file (expand-file-name "here.org" dir) (insert "here\n"))
      (my/pg-test--git dir "add" "-A")
      (my/pg-test--git dir "commit" "--quiet" "-m" "here")
      (setq head (my/pg-test--git dir "rev-parse" "HEAD"))
      (should (string-match-p "diverged -- 1 ahead, 1 behind" (my/pg-test--report dir)))
      (should (equal (my/pg-test--git dir "rev-parse" "HEAD") head)))))

(ert-deftest my/pg-test-repositories-for-auto-commit ()
  "The automatic commits get the projects that are repositories, and no
other folder."
  (my/pg-test--with-projects
    (let ((repo (my/pg-test--project projects "essay")))
      (my/pg-test--project projects "plain")
      (my/project-git-init "essay" t)
      (should (equal (my/project-git-repositories) (list repo))))))

(ert-deftest my/pg-test-only-this-module-changes-remotes ()
  "SAFETY.org 3.1: no other module runs git remote with add, set-url,
remove or rename.  A search of the code for those words next to
\"remote\", so it finds what is written that way -- not a remote changed
through a variable or by Magit on a key (TESTING.org, rule 7)."
  (let ((offenders nil))
    (dolist (file (directory-files-recursively (expand-file-name "modules" my/test-repo) "\\.el\\'"))
      (unless (string-match-p "439-project-git\\.el\\'" file)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "\"remote\"[ \t\n]+\\(?:(if[^\n]*\\)?\"\\(add\\|set-url\\|remove\\|rm\\|rename\\)\""
                  nil t)
            (push (format "%s:%d" (file-name-nondirectory file) (line-number-at-pos)) offenders)))))
    (should (null offenders))
    ;; The search finds this module's own call.
    (with-temp-buffer
      (insert-file-contents (expand-file-name "modules/400-notes-extensions/439-project-git.el" my/test-repo))
      (should (re-search-forward
               "\"remote\"[ \t\n]+\\(?:(if[^\n]*\\)?\"\\(add\\|set-url\\|remove\\|rm\\|rename\\)\""
               nil t)))))

(provide 'test-project-git)
;;; test-project-git.el ends here
