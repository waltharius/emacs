;;; 07-git.el --- Git integration with auto-commit -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: no

;;; Commentary:
;; Magit, plus automatic commits and pushes for the repositories that
;; hold text rather than decisions.
;;
;; Runs after five minutes of idleness and again on exit.  Which
;; repositories are covered comes from
;; `my/auto-commit-repository-sources', to which other modules
;; contribute; this one contributes ~/notes/.
;;
;; Before every push, and once when Emacs starts, each repository is
;; brought up to date with its upstream (`git pull --rebase'), so that
;; two machines editing the same notes one after the other stay in
;; step.  The start-up pull and the idle cycle run git in the background
;; (see "IN THE BACKGROUND"); only the exit commit waits for git.  A conflict is never resolved automatically: the pull is
;; undone, nothing is pushed, and a warning says how to resolve it.
;;
;; Docs: ~/.emacs.d/function_helper.org::#auto-commit

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function magit-status-setup-buffer "magit-status" (&optional directory))

;; ============================================================
;; MAGIT: Git interface for Emacs
;; ============================================================

(use-package magit
  :ensure t
  :bind (("C-x g"   . magit-status)
         ("C-x M-g" . magit-dispatch)
         ("C-c g s" . magit-status)
         ("C-c g l" . magit-log-current)
         ("C-c g b" . magit-blame))
  :config
  (setq magit-refresh-status-buffer t)
  (setq git-commit-summary-max-length 72)
  (setq git-commit-fill-column 72)
  (add-hook 'after-save-hook 'magit-after-save-refresh-status t))


;; ============================================================
;; AUTO-COMMIT AND PUSH
;; ============================================================
;; One mechanism, several repositories.  There used to be two nearly
;; identical functions, one per directory, which meant adding a third
;; directory meant copying thirty lines and remembering to change every
;; string in them.
;;
;; WHAT IS COMMITTED AUTOMATICALLY AND WHAT IS NOT.  Notes and writing
;; projects are a working log: text accumulates, "Auto-commit: <date>"
;; is an accurate description of what happened, and the value is being
;; able to get yesterday's paragraph back.  The Emacs configuration is
;; not: each change there is a decision with a reason worth writing
;; down, and an auto-commit buries the reason and silently absorbs
;; half-finished edits.  That asymmetry is why the config is opt-in.
;;
;; PUSHING is what makes any of this a backup.  A local commit protects
;; against an editing mistake; only a push protects against the disk.
;;
;; TWO MOMENTS.  On five minutes of idleness, and on exit.  Idleness is
;; the important one: it happens while the machine is still on and the
;; network still reachable, and it costs nothing because nobody is
;; typing.  Exit is the safety net.

(defgroup my/git nil
  "Automatic commits of the notes repository (07-git.el)."
  :tag "Automatic commits"
  :group 'mypks-git)

(defun my/auto-commit--notes-directory ()
  "Return the notes folder, the first repository committed automatically."
  (list (expand-file-name my-notes-dir)))

(defvar my/auto-commit-repository-sources
  (list #'my/auto-commit--notes-directory)
  "Functions returning directories to auto-commit.

A list of functions rather than a list of directories so that a module
can contribute repositories this one has never heard of, and so that
the set can be computed rather than fixed: 39-project-git.el adds every
writing project, and the number of those changes during a session;
37-tasks.el adds the planner folder.

A variable for modules, not an option: it was a `defcustom' holding a
lambda, which Customize can neither show nor save meaningfully.")

(defcustom my/auto-commit-config-enabled nil
  "When non-nil, the Emacs configuration repository is auto-committed too.

Disabled 2026-08.  Notes are a working log and \"Auto-commit: <date>\"
on exit is an accurate description of what happened to them.  Config
changes are deliberate and each one has a reason worth writing down; an
auto-commit on exit buries that reason and, worse, silently absorbs
half-finished edits into the history.  `my/commit-config-now' still
commits by hand."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-push t
  "When non-nil, push after committing.

A commit protects against an editing mistake.  Only a push protects
against the disk, and the local GitLab exists for exactly that.

Turned off, nothing reaches the other machines -- every cycle and
`C-c v ?' say so.  To keep one folder from pushing (a test copy of the
notes), list it in `my/auto-commit-no-push-directories' instead."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-no-push-directories nil
  "Repositories committed automatically but never pushed.

For a copy of the notes with the same remote as the original, made to
test a new notes folder: its commits must not reach the server.  Added
by the question after such a copy (00-core.el).  Every other repository
keeps pushing; until 2026-10-16 that question turned pushing off for
all of them, and switching back to the original folder left it off."
  :type '(repeat directory)
  :group 'my/git)

(defun my/auto-commit--push-p (dir)
  "Return non-nil when commits in DIR are to be pushed."
  (and my/auto-commit-push
       (not (member (file-name-as-directory (expand-file-name dir))
                    (mapcar (lambda (d) (file-name-as-directory (expand-file-name d)))
                            my/auto-commit-no-push-directories)))))

(defcustom my/auto-commit-pull t
  "When non-nil, pull from the upstream at startup and before each push.

The notes live on several machines and are synchronised
through the local GitLab only.  Without pulling, the second machine
keeps writing on top of an old state: its push is rejected and its
automatic commits silently diverge from the server.  Pulling with
--rebase puts this machine's commits on top of what the other one
pushed, which is exactly what happened in time when the machines are
used one after the other."
  :type 'boolean
  :group 'my/git)

(defcustom my/auto-commit-idle-seconds 300
  "Seconds of idleness before an automatic commit and push.

Five minutes: long enough that it never fires mid-sentence, short
enough that a coffee break is a backup.  Takes effect at once."
  :type 'integer
  :set (my/settings-apply-on-set #'my/auto-commit--arm-timer)
  :group 'my/git)

(defcustom my/auto-commit-confirm-exit t
  "When non-nil, quitting Emacs asks first if work is not on the server.

Before Emacs exits, every repository is committed and pushed once more.
If one still has uncommitted changes, commits its server does not have,
a stopped rebase or a lock left by an interrupted git command, the
question names it, and answering no keeps Emacs open.  Away from the
server this asks every time, which is the point: the other machine
will not see the work."
  :type 'boolean
  :group 'my/git)

(defvar my/auto-commit-log-buffer "*auto-commit*"
  "Buffer collecting git output from automatic commits and pushes.")

(defun my/auto-commit--env ()
  "Return a process environment in which git cannot hang.

`GIT_TERMINAL_PROMPT=0' stops git asking for credentials it has no
terminal to ask on.  The SSH timeout bounds the other way this can
hang: a push on `kill-emacs-hook' runs synchronously, so an unreachable
server would otherwise hold Emacs open for the full TCP timeout, and
the symptom would be an editor that will not close."
  (append '("GIT_TERMINAL_PROMPT=0"
            "GIT_SSH_COMMAND=ssh -o ConnectTimeout=5 -o BatchMode=yes")
          process-environment))

(defun my/auto-commit--log (dir args output status)
  "Record in `my/auto-commit-log-buffer' that git ARGS in DIR gave OUTPUT, STATUS."
  (with-current-buffer (get-buffer-create my/auto-commit-log-buffer)
    (goto-char (point-max))
    (insert (format "\n[%s] %s\n$ git %s\n%s(exit %s)\n"
                    (format-time-string "%Y-%m-%d %H:%M:%S")
                    dir (string-join args " ")
                    (if (string-empty-p output) "" (concat output "\n"))
                    status))))

(defun my/auto-commit--git (dir &rest args)
  "Run git ARGS in DIR, logging output.  Return the exit status."
  (let* ((default-directory (file-name-as-directory dir))
         (process-environment (my/auto-commit--env))
         output
         (status (with-temp-buffer
                   (prog1 (apply #'call-process "git" nil t nil args)
                     (setq output (string-trim (buffer-string)))))))
    (my/auto-commit--log dir args output status)
    status))

(defun my/auto-commit--git-async (dir args callback)
  "Run git ARGS in DIR without blocking Emacs; log like `my/auto-commit--git'.
CALLBACK receives the exit status (-1 when git was killed by a signal).
The same environment as the blocking variant, so git cannot stop on a
credential prompt either."
  (let* ((default-directory (file-name-as-directory dir))
         (process-environment (my/auto-commit--env))
         (buffer (generate-new-buffer " *auto-commit git*")))
    (make-process
     :name "auto-commit-git"
     :buffer buffer
     :command (cons "git" args)
     :connection-type 'pipe
     :noquery t
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (let ((status (if (eq (process-status proc) 'exit)
                           (process-exit-status proc)
                         -1))
               (output (if (buffer-live-p buffer)
                           (with-current-buffer buffer (string-trim (buffer-string)))
                         "")))
           (when (buffer-live-p buffer) (kill-buffer buffer))
           (my/auto-commit--log dir args output status)
           (funcall callback status)))))))

(defun my/auto-commit--query (dir &rest args)
  "Run git ARGS in DIR for a local answer: its output lines, or nil on failure.
No shell, so nothing in a file name is ever interpreted; standard error
is discarded, so a failure never passes for an answer.  For questions
that read the repository only (status, rev-parse, rev-list) and take
milliseconds; anything that may reach the network goes through
`my/auto-commit--git-async'."
  (let ((default-directory (file-name-as-directory dir))
        (process-environment (my/auto-commit--env)))
    (with-temp-buffer
      (when (eq 0 (apply #'call-process "git" nil '(t nil) nil args))
        (split-string (buffer-string) "\n" t)))))

(defun my/auto-commit--dirty-p (dir)
  "Return non-nil when DIR has uncommitted changes."
  (and (my/auto-commit--query dir "status" "--porcelain") t))

(defun my/auto-commit--unpushed-p (dir)
  "Return non-nil when DIR has commits its upstream does not."
  (let ((count (car (my/auto-commit--query dir "rev-list" "--count" "@{u}..HEAD"))))
    (and count (not (equal count "0")))))

;; ============================================================
;; PULL: KEEPING SEVERAL MACHINES IN STEP
;; ============================================================
;; `git pull --rebase' replays this machine's commits on top of the
;; upstream.  It runs on a committed tree only: with changes not yet
;; committed the result is `dirty' and nothing is pulled until the next
;; cycle has committed them (`--autostash', used until 2026-10-24, could
;; leave conflict markers in a file after a pull that exited 0).  Files
;; with markers, from that or from any other git command, keep the
;; repository from being committed or pushed (`my/auto-commit--busy-p').
;; Three outcomes of a pull:
;;
;;   ok        up to date; buffers visiting changed files are reloaded
;;             by `global-auto-revert-mode' (02-editing.el)
;;   offline   the server could not be reached (away from home, GitLab
;;             down).  Nothing changes; work goes on locally and is
;;             pushed by a later cycle.
;;   conflict  the same lines were changed here and on the server.  The
;;             rebase is aborted at once, so the repository is exactly
;;             as before the pull and no file holds conflict markers.
;;             Nothing is pushed and a warning appears once.  Automatic
;;             commits continue locally; `my/auto-commit-resolve' runs
;;             the pull by hand and opens Magit on the conflict.
;;
;; While a rebase or merge is in progress (someone resolving a conflict
;; by hand), the repository is left alone completely: an automatic
;; `git add -A' at that moment would commit the conflict markers.

(defvar my/auto-commit--conflicts nil
  "Repositories whose last pull stopped on a conflict (already warned).")

(defun my/auto-commit--git-path (dir path)
  "Return the absolute path of PATH inside DIR's git directory."
  (expand-file-name (or (car (my/auto-commit--query dir "rev-parse" "--git-path" path))
                        (concat ".git/" path))
                    (file-name-as-directory dir)))

(defun my/auto-commit--message-buffers (&optional dir)
  "Return the buffers where git waits for a commit message, in DIR if given.
A buffer of with-editor (Magit's `c c', C-c v c) visiting a file in a
.git folder: git started, opened the message and waits until it is
finished (C-c C-c) or cancelled (C-c C-k)."
  (seq-filter
   (lambda (buffer)
     (let ((file (buffer-file-name buffer)))
       (and file
            (buffer-local-value 'with-editor-mode buffer)
            (string-match-p "/\\.git/" file)
            (or (null dir)
                (string-prefix-p (file-name-as-directory (expand-file-name ".git" dir))
                                 (expand-file-name file))))))
   (seq-filter (lambda (b) (local-variable-p 'with-editor-mode b)) (buffer-list))))

(defun my/auto-commit--unmerged-p (dir)
  "Return the files of DIR that hold an unresolved conflict, or nil.
Git's own list of unmerged paths.  A pull can leave them without any
rebase or merge in progress: `--autostash' re-applies the local
changes after a successful rebase, and when they touch the lines just
pulled, git writes conflict markers into the file and still exits 0
(found 2026-10-24 by the outside audits; reproduced with git 2.43).
`git add -A' would then commit the markers and push them."
  (my/auto-commit--query dir "diff" "--name-only" "--diff-filter=U"))

(defun my/auto-commit--busy-p (dir)
  "Return non-nil when DIR must be left alone for now.
A rebase or merge in progress, files with an unresolved conflict
\(`my/auto-commit--unmerged-p'), or a commit message being written there.
In the last case a commit made meanwhile moves HEAD under the waiting
git, whose own commit then fails (git: cannot lock ref HEAD); found
2026-10-22 when C-c v c began to work."
  (or (seq-some (lambda (path)
                  (file-exists-p (my/auto-commit--git-path dir path)))
                '("rebase-merge" "rebase-apply" "MERGE_HEAD"))
      (my/auto-commit--unmerged-p dir)
      (my/auto-commit--message-buffers dir)))

(defun my/auto-commit--has-upstream-p (dir)
  "Return non-nil when DIR's current branch tracks an upstream branch."
  (and (my/auto-commit--query dir "rev-parse" "--abbrev-ref"
                              "--symbolic-full-name" "@{u}")
       t))

(defun my/auto-commit--head (dir)
  "Return the commit DIR's HEAD points to, or nil before the first commit."
  (car (my/auto-commit--query dir "rev-parse" "HEAD")))

(defun my/auto-commit--warn-conflict (dir)
  "Warn once that pulling DIR stopped on a conflict."
  (unless (member dir my/auto-commit--conflicts)
    (push dir my/auto-commit--conflicts)
    (display-warning
     'auto-commit
     (format "%s: the server has changes to the same lines as this machine.

Nothing was overwritten and nothing was pushed; the pull was undone.
Your work keeps being committed locally.  To merge both versions:

  M-x my/auto-commit-resolve   pull again and open Magit on the conflict
                               (resolve in the file with C-c ^ ...,
                               then `r r' in Magit to continue)

Details: M-x my/auto-commit-show-log"
             (abbreviate-file-name dir))
     :warning)))

(defun my/auto-commit--pull (dir)
  "Rebase DIR's local commits onto its upstream.

Return `ok', `offline', `conflict', `busy', `dirty' or `no-upstream'.
On a conflict the rebase is aborted, leaving DIR exactly as it was.

`dirty': DIR has changes not committed yet, so it is not pulled.  The
pull used `--autostash' until 2026-10-24, which can write conflict
markers into a file and exit 0 (`my/auto-commit--unmerged-p'); without
it git itself refuses to rebase a dirty tree, which is the guard when a
file is saved between the check and the pull.  The next cycle commits
the changes first, then pulls."
  (cond
   ((my/auto-commit--busy-p dir) 'busy)
   ((not (my/auto-commit--has-upstream-p dir)) 'no-upstream)
   ((my/auto-commit--dirty-p dir) 'dirty)
   ((eq 0 (my/auto-commit--git dir "pull" "--rebase"))
    (setq my/auto-commit--conflicts (delete dir my/auto-commit--conflicts))
    'ok)
   (t (my/auto-commit--pull-failed dir))))

(defun my/auto-commit--pull-failed (dir)
  "Return what a failed pull of DIR means; undo a conflicting rebase."
  (cond
   ((my/auto-commit--busy-p dir)
    (my/auto-commit--git dir "rebase" "--abort")
    (my/auto-commit--warn-conflict dir)
    'conflict)
   ((my/auto-commit--dirty-p dir) 'dirty)
   (t 'offline)))

(defun my/auto-commit--pull-async (dir callback)
  "Like `my/auto-commit--pull', without blocking on the network.
CALLBACK receives the same result symbol.  Only `git pull' runs in the
background; the local checks before it and the abort of a conflicting
rebase after it take milliseconds and stay synchronous."
  (cond
   ((my/auto-commit--busy-p dir) (funcall callback 'busy))
   ((not (my/auto-commit--has-upstream-p dir)) (funcall callback 'no-upstream))
   ((my/auto-commit--dirty-p dir) (funcall callback 'dirty))
   (t
    (my/auto-commit--git-async
     dir '("pull" "--rebase")
     (lambda (status)
       (funcall callback
                (cond
                 ((eq status 0)
                  (setq my/auto-commit--conflicts (delete dir my/auto-commit--conflicts))
                  'ok)
                 (t (my/auto-commit--pull-failed dir)))))))))

(defun my/auto-commit--pull-line (dir result updated)
  "Return the message line for pulling DIR with RESULT, or nil for none.
UPDATED is non-nil when HEAD moved."
  (let ((name (file-name-nondirectory (directory-file-name dir))))
    (pcase result
      ('ok (when updated (format "%s: updated from the server" name)))
      ('offline (format "%s: server unreachable, working offline" name))
      ('conflict (format "%s: CONFLICT, see *Warnings*" name))
      ('busy (if (my/auto-commit--unmerged-p dir)
                 (format "%s: CONFLICT markers in files, see *Warnings*" name)
               (format "%s: rebase or merge in progress" name)))
      ('dirty (format "%s: changes not committed yet, not pulled" name))
      (_ nil))))

;; ============================================================
;; WHEN SOMETHING STOPS IT
;; ============================================================
;; The idle cycle is quiet by design, and that made two failures
;; invisible: a `.git/index.lock' left by a git command that was
;; interrupted (Emacs killed during the exit commit, a crash), on which
;; every `git add' fails; and a rebase or merge left in progress, during
;; which the repository is skipped on purpose.  Either stopped commits
;; and pushes for good while the editor looked normal.  After every
;; cycle each repository is now asked what, if anything, keeps its work
;; off the server, and a new answer is shown as a warning -- once, until
;; it changes or clears.

(defvar my/auto-commit--reported nil
  "Alist of (DIRECTORY . REASON) already shown as a warning.")

(defun my/auto-commit--locked-p (dir)
  "Return non-nil when DIR's index is locked by another git command."
  (file-exists-p (my/auto-commit--git-path dir "index.lock")))

(defconst my/auto-commit--push-off-reason
  "commits not pushed: pushing is turned off"
  "The reason `my/auto-commit-pending' gives when pushing was turned off.")

(defun my/auto-commit-pending (dir)
  "Return why DIR's work is not on its server, or nil when it is.

Nil for a repository without an upstream branch, a local one by
choice.  Unpushed commits while pushing is turned off for DIR are
reported too, with their own reason: a switch turned off and forgotten
looks exactly like a push that silently stopped."
  (setq dir (expand-file-name dir))
  (when (file-directory-p (expand-file-name ".git" dir))
    (cond
     ((my/auto-commit--unmerged-p dir) "files hold conflict markers")
     ((my/auto-commit--busy-p dir) "a rebase or merge is in progress")
     ((my/auto-commit--locked-p dir) "git is locked (.git/index.lock)")
     ((my/auto-commit--dirty-p dir) "changes not committed")
     ((not (and (my/auto-commit--has-upstream-p dir)
                (my/auto-commit--unpushed-p dir)))
      nil)
     ((my/auto-commit--push-p dir) "commits not pushed")
     (t my/auto-commit--push-off-reason))))

(defun my/auto-commit--advice (dir reason)
  "Return what to do about REASON in DIR, as text."
  (let ((git (abbreviate-file-name (expand-file-name ".git" dir))))
    (pcase reason
      ("git is locked (.git/index.lock)"
       (format "  A git command was interrupted and left its lock.  If no git
  is running now, remove it:  rm %s/index.lock" git))
      ("files hold conflict markers"
       (format "  A pull left both versions in files, between <<<<<<< and >>>>>>>:
  %s
  Nothing is committed or pushed until they are resolved.  Open them
  with M-x my/auto-commit-resolve (Magit), keep the right text (C-c ^
  in the file), stage each file; the local version is also kept by git
  in its stash list."
               (string-join (my/auto-commit--unmerged-p dir) ", ")))
      ("a rebase or merge is in progress"
       "  Finish or abort it: M-x my/auto-commit-resolve, or in Magit
  `r r' (continue) / `r a' (abort).")
      ("changes not committed"
       "  The commit failed; the reason is in the log (C-c v l).")
      ((pred (equal my/auto-commit--push-off-reason))
       (if my/auto-commit-push
           (format "  %s is in `my/auto-commit-no-push-directories' (C-c n , ,
  -> Tools -> Git).  Remove it there to push again."
                   (abbreviate-file-name dir))
         "  `my/auto-commit-push' is off: M-x customize-option RET
  my/auto-commit-push (or C-c n , , -> Tools -> Git).  Turn it on,
  Apply and Save; C-c v a pushes at once."))
      (_
       "  The server was unreachable or refused the push; the log
  (C-c v l) says which.  Pushed by the next cycle once it is back."))))

(defun my/auto-commit--report (dirs)
  "Warn about every repository in DIRS whose work is not on its server.
Each (directory . reason) is shown once; it is forgotten when it clears,
so that the next failure is shown again."
  (let (new)
    (dolist (dir dirs)
      (let* ((dir (expand-file-name dir))
             (reason (condition-case err (my/auto-commit-pending dir)
                       (error (error-message-string err))))
             (old (assoc dir my/auto-commit--reported)))
        (cond
         ((null reason)
          (setq my/auto-commit--reported (delq old my/auto-commit--reported)))
         ((equal reason (cdr old)) nil)
         (t
          (setq my/auto-commit--reported
                (cons (cons dir reason) (delq old my/auto-commit--reported)))
          (push (cons dir reason) new)))))
    (when new
      (display-warning
       'auto-commit
       (concat "Work that is NOT on the server:\n\n"
               (mapconcat (lambda (entry)
                            (format "%s: %s\n%s"
                                    (abbreviate-file-name (car entry))
                                    (cdr entry)
                                    (my/auto-commit--advice (car entry) (cdr entry))))
                          (nreverse new) "\n\n")
               "\n\nCheck at any time: C-c v ?   Git output: C-c v l")
       :warning))))

;;;###autoload
(defun my/auto-commit-status ()
  "Say, for every auto-committed repository, whether its work is on the server."
  (interactive)
  (let ((lines (mapcar (lambda (dir)
                         (format "%s: %s" (abbreviate-file-name dir)
                                 (or (ignore-errors (my/auto-commit-pending dir))
                                     "on the server")))
                       (seq-filter (lambda (d) (file-directory-p
                                                (expand-file-name ".git" d)))
                                   (my/auto-commit-directories)))))
    (message "%s" (string-join lines "\n"))
    lines))

(defun my/auto-commit--message (dir)
  "Return the commit message for what is staged in DIR."
  ;; core.quotePath=false: without it git writes a Polish title as
  ;; "za\305\274..." in quotes, and the message is unreadable.
  (let ((files (my/auto-commit--query dir "-c" "core.quotePath=false"
                                      "diff" "--cached" "--name-only")))
    (format "Auto-commit: %s\n\nChanged (%d):\n%s%s"
            (format-time-string "%Y-%m-%d %H:%M")
            (length files)
            (mapconcat #'file-name-nondirectory (seq-take files 5) "\n")
            (if (> (length files) 5)
                (format "\n... and %d more" (- (length files) 5))
              ""))))

(defun my/auto-commit-repository-async (dir callback)
  "Commit, pull and push DIR in the background; then call CALLBACK.
CALLBACK receives a short description of what happened, or nil when
nothing did.  Each step starts from the end of the one before:

  add -A -> commit -> pull --rebase -> push

Every step is skipped when there is nothing for it; a pull that did not
end `ok' (offline, conflict) keeps the push from running.  An error in
any step ends the chain with \"ERROR ...\" as the description, so
CALLBACK is always called, exactly once."
  (setq dir (expand-file-name dir))
  (if (not (and (file-directory-p dir)
                (file-directory-p (expand-file-name ".git" dir))
                (not (my/auto-commit--busy-p dir))))
      (funcall callback nil)
    (let ((name (file-name-nondirectory (directory-file-name dir)))
          (called nil)
          (committed nil)
          (pulled nil)
          (pull-result nil))
      (cl-labels
          ((done (text)
             (unless called
               (setq called t)
               (funcall callback text)))
           (safely (fn &rest args)
             (condition-case err
                 (apply fn args)
               (error (done (format "%s: ERROR %s" name (error-message-string err))))))
           (finish (pushed)
             (let ((parts (delq nil (list (and committed "committed")
                                          (and pulled "pulled")
                                          (and pushed "pushed")
                                          (and (eq pull-result 'offline)
                                               "server unreachable")
                                          (and (eq pull-result 'conflict)
                                               "CONFLICT, not pushed")
                                          (and (eq pull-result 'dirty)
                                               "not pulled: changes not committed")))))
               (done (and parts (format "%s: %s" name (string-join parts ", "))))))
           (push-step ()
             (if (and (my/auto-commit--push-p dir)
                      (memq pull-result '(nil ok no-upstream))
                      (my/auto-commit--unpushed-p dir))
                 (my/auto-commit--git-async
                  dir '("push")
                  (lambda (status) (safely #'finish (eq status 0))))
               (finish nil)))
           (pull-step ()
             ;; Pull before pushing: a push on top of an old state is
             ;; rejected, and a rejected push is easy to miss.
             (if (not my/auto-commit-pull)
                 (push-step)
               (let ((before (my/auto-commit--head dir)))
                 (my/auto-commit--pull-async
                  dir
                  (lambda (result)
                    (safely
                     (lambda ()
                       (setq pull-result result
                             pulled (and (eq result 'ok)
                                         (not (equal before (my/auto-commit--head dir)))))
                       (push-step))))))))
           (commit-step ()
             (if (not (my/auto-commit--dirty-p dir))
                 (pull-step)
               ;; Arguments, not a shell: file names with apostrophes,
               ;; semicolons or spaces -- a Denote collection with Polish
               ;; titles has plenty -- are never interpreted.
               (my/auto-commit--git-async
                dir '("add" "-A")
                (lambda (status)
                  (safely
                   (lambda ()
                     ;; A failed add (a lock left by an interrupted git)
                     ;; stops the chain: no commit, pull or push on a
                     ;; half-staged tree.
                     (unless (eq status 0)
                       (error "git add failed (C-c v l shows why)"))
                     ;; Listed AFTER staging, from the index: new files
                     ;; included, and no HEAD needed.
                     (my/auto-commit--git-async
                      dir (list "commit" "-m" (my/auto-commit--message dir))
                      (lambda (status)
                        (safely
                         (lambda ()
                           (setq committed (eq status 0))
                           (pull-step))))))))))))
        (safely #'commit-step)))))

(defun my/auto-commit--await (start &optional limit)
  "Call START with a callback and wait until it is called; return its value.
Waits at most LIMIT seconds (default 120): the blocking path of the
exit commit, built on the same chain as the background cycle so that
there is one implementation of what a cycle does.  Timers and process
output are served while waiting."
  (let ((done nil)
        (value nil)
        (deadline (+ (float-time) (or limit 120))))
    (funcall start (lambda (v) (setq value v done t)))
    (while (and (not done) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    value))

(defun my/auto-commit-repository (dir)
  "Commit and push DIR when there is anything to commit or push; wait for it.
Returns a short description of what happened, or nil when nothing did.
The blocking form of `my/auto-commit-repository-async'."
  (my/auto-commit--await
   (lambda (callback) (my/auto-commit-repository-async dir callback))))

(defun my/auto-commit-directories ()
  "Return every directory that should be committed automatically."
  (delete-dups
   (append (seq-mapcat (lambda (fn) (ignore-errors (funcall fn)))
                       my/auto-commit-repository-sources)
           (when my/auto-commit-config-enabled
             (list (expand-file-name user-emacs-directory))))))

(defun my/auto-commit--save-buffers ()
  "Save modified buffers visiting files inside the auto-committed repositories.

Without this, the exit-time commit records what is on disk while the
last paragraph is still only in a buffer.  Nothing is lost -- the next
session's idle timer catches it -- but a commit that reports success
and does not contain the work is worse than no commit, because it will
be believed.

Only files under those directories, and never anything inside `.git/':
saving every modified buffer would reach scratch buffers and files
opened for reference, and git's own COMMIT_EDITMSG is not text anyone
wants preserved."
  (let ((dirs (my/auto-commit-directories)))
    (dolist (buffer (buffer-list))
      (let ((file (buffer-file-name buffer)))
        (when (and file
                   (buffer-modified-p buffer)
                   (not (string-match-p "/\\.git/" file))
                   (seq-some (lambda (dir)
                               (string-prefix-p (file-name-as-directory dir)
                                                (expand-file-name file)))
                             dirs))
          (with-current-buffer buffer
            (condition-case err
                (save-buffer)
              ;; Shown, not swallowed: an unsaved buffer means the
              ;; commit that follows does not hold that work.
              (error
               (display-warning
                'auto-commit
                (format "%s could not be saved before the automatic commit: %s"
                        (buffer-name buffer) (error-message-string err))
                :warning)))))))))

;; ============================================================
;; IN THE BACKGROUND
;; ============================================================
;; The idle cycle used to run git with `call-process': add, commit,
;; pull and push one after another, Emacs frozen for the whole network
;; round trip -- coming back to the keyboard during it meant typing
;; into a frozen editor.  Now each repository is a chain of background
;; processes (`my/auto-commit-repository-async'), the repositories one
;; after another (`my/auto-commit--cycle-next'), and Emacs stays usable.
;;
;; One cycle at a time: `my/auto-commit--cycle-running' is set while one
;; runs, the idle timer skips then, and the start-up pull counts as
;; running too.  Saving buffers happens before the first process starts,
;; so the commit holds what was typed.
;;
;; The exit commit still waits (`my/auto-commit-all'): Emacs must not
;; quit before git is done.  It waits through `my/auto-commit--await'
;; on the same chain, so there is one definition of a cycle.

(defvar my/auto-commit--cycle-running nil
  "Non-nil while a commit cycle runs in the background: when it started.")

;; Defined below, under WHEN IT RUNS, with the start-up pull.
(defvar my/auto-commit--startup-pull-running)
(defvar my/auto-commit-startup-pull-wait)

(defun my/auto-commit--busy-in-background-p ()
  "Non-nil while the start-up pull or a background cycle runs."
  (or my/auto-commit--startup-pull-running my/auto-commit--cycle-running))

(defun my/auto-commit--wait-for-background ()
  "Wait, at most `my/auto-commit-startup-pull-wait' seconds, for background git.
Two git commands in one repository at once end with one of them
refused on the index lock."
  (let ((deadline (+ (float-time) my/auto-commit-startup-pull-wait)))
    (while (and (my/auto-commit--busy-in-background-p)
                (< (float-time) deadline))
      (accept-process-output nil 0.1))))

(defun my/auto-commit--cycle-next (dirs results callback)
  "Commit the first of DIRS in the background, then the rest.
RESULTS are the descriptions so far; CALLBACK receives all of them."
  (if (null dirs)
      (funcall callback (nreverse results))
    (my/auto-commit-repository-async
     (car dirs)
     (lambda (text)
       (my/auto-commit--cycle-next (cdr dirs)
                                   (if text (cons text results) results)
                                   callback)))))

(defun my/auto-commit--cycle (callback &optional quiet)
  "Save, then commit and push every repository in the background.
CALLBACK receives the list of descriptions.  The summary goes to the
echo area, or with QUIET only to *Messages*; what is still not on the
server is reported as a warning (`my/auto-commit--report')."
  (setq my/auto-commit--cycle-running (current-time))
  (condition-case err
      (progn
        (my/auto-commit--save-buffers)
        (let ((dirs (my/auto-commit-directories)))
          (my/auto-commit--cycle-next
           dirs nil
           (lambda (results)
             (setq my/auto-commit--cycle-running nil)
             (condition-case err
                 (progn
                   (when results
                     (let ((inhibit-message quiet))
                       (message "%s" (string-join results "; "))))
                   (my/auto-commit--report dirs))
               (error (display-warning
                       'auto-commit
                       (format "Reporting the automatic commit failed: %s"
                               (error-message-string err))
                       :warning)))
             (funcall callback results)))))
    (error
     (setq my/auto-commit--cycle-running nil)
     (display-warning 'auto-commit
                      (format "The automatic commit failed: %s"
                              (error-message-string err))
                      :warning)
     (funcall callback nil))))

;;;###autoload
(defun my/auto-commit-now ()
  "Commit and push every repository now, in the background (C-c v a).
The echo area says what happened when git is done; Emacs stays usable
meanwhile."
  (interactive)
  (if (my/auto-commit--busy-in-background-p)
      (message "A commit or pull is already running; its result follows")
    (message "Committing and pushing in the background...")
    (my/auto-commit--cycle #'ignore)))

(defun my/auto-commit-all ()
  "Commit and push every repository that needs it, and wait until git is done.
For the way out of Emacs, which must not end before the push.  Waits
first for background git (`my/auto-commit--wait-for-background').
Returns the list of descriptions."
  (my/auto-commit--wait-for-background)
  (my/auto-commit--await #'my/auto-commit--cycle))

;;;###autoload
(defun my/auto-commit-show-log ()
  "Show the git output of automatic commits and pushes."
  (interactive)
  (pop-to-buffer (get-buffer-create my/auto-commit-log-buffer)))

;;;###autoload
(defun my/auto-commit-pull-all ()
  "Bring every auto-committed repository up to date with its upstream."
  (interactive)
  (my/auto-commit--wait-for-background)
  (let ((results
         (delq nil
               (mapcar
                (lambda (dir)
                  (when (file-directory-p (expand-file-name ".git" dir))
                    (let* ((before (my/auto-commit--head dir))
                           (result (my/auto-commit--pull dir)))
                      (my/auto-commit--pull-line
                       dir result (not (equal before (my/auto-commit--head dir)))))))
                (mapcar #'expand-file-name (my/auto-commit-directories))))))
    (when results
      (message "%s" (string-join results "; ")))
    results))

;;;###autoload
(defun my/auto-commit-resolve (&optional dir)
  "Pull DIR (default ~/notes/) with --rebase and leave a conflict open in Magit.

The automatic pull undoes a conflicting rebase so that nothing is ever
left half-done.  This command does the same pull by hand and stops on
the conflict: Magit lists the conflicted files, `C-c ^' (smerge) picks
between the versions inside a file, and `r r' in Magit continues the
rebase.  The next automatic cycle pushes the result."
  (interactive)
  (let* ((dir (file-name-as-directory
               (expand-file-name (or dir my-notes-dir))))
         (default-directory dir))
    (my/auto-commit--save-buffers)
    (when (my/auto-commit--dirty-p dir)
      (my/auto-commit-repository dir))
    (unless (my/auto-commit--busy-p dir)
      (my/auto-commit--git dir "pull" "--rebase"))
    (setq my/auto-commit--conflicts (delete dir my/auto-commit--conflicts))
    (magit-status-setup-buffer dir)))

;; ============================================================
;; WHEN IT RUNS
;; ============================================================

;; THE START-UP PULL, IN THE BACKGROUND.  It used to run synchronously
;; from `after-init-hook', so Emacs showed nothing until every repository
;; had been pulled -- up to the SSH connect timeout (5 s) per repository
;; away from home, with the notes, the settings folder, the planner and
;; every writing project.  Now `git pull' runs as a background process,
;; one repository after another, and Emacs is usable at once.
;;
;; What changes: `desktop-save-mode' reopens the last session's files
;; before the pull has landed, so a buffer may first show the previous
;; version; `global-auto-revert-mode' (02-editing.el) reloads it when the
;; pull changes the file.  A buffer edited in the meantime is not
;; reloaded, and Emacs asks before the first change to a buffer whose
;; file changed on disk, as always.
;;
;; Nothing else runs git in these repositories meanwhile: the idle cycle
;; and C-c v a skip while the pull runs, and `my/auto-commit-all' (the
;; exit commit) waits for it, at most `my/auto-commit-startup-pull-wait'.
;;
;; Work that must see the pulled files -- the personal dictionary of
;; 03-spelling.el, which adds this machine's words to the file the other
;; machine pushed -- asks `my/auto-commit-after-startup-pull' to run it
;; when the pull is done, or at once when there is none.
;; `my/auto-commit-pull-done-hook' runs at the same moment.

(defcustom my/auto-commit-startup-pull-wait 30
  "Seconds a commit waits for the start-up pull to finish.
Also the time after which the start-up pull counts as finished even if
git has not returned (a stalled transfer), so that what waits for it
runs and the idle cycle resumes."
  :type 'integer
  :group 'my/git)

(defvar my/auto-commit-pull-done-hook nil
  "Hook run once the start-up pull of every repository has finished.
Each function receives the list of message lines (possibly empty).")

(defvar my/auto-commit--startup-pull-running nil
  "Non-nil while the start-up pull runs: the time it started.")

(defvar my/auto-commit--startup-pull-waiting nil
  "Functions to call once the start-up pull has finished.")

(defvar my/auto-commit--startup-pull-watchdog nil
  "Timer that ends a start-up pull which never returned.")

(defun my/auto-commit-after-startup-pull (function)
  "Call FUNCTION, of no arguments, once the start-up pull has finished.
At once when no start-up pull is running (none started, already done,
or pulling turned off)."
  (if my/auto-commit--startup-pull-running
      (add-to-list 'my/auto-commit--startup-pull-waiting function t)
    (funcall function)))

(defun my/auto-commit--startup-pull-finish (lines)
  "End the start-up pull: report LINES, run what waited for it.
Each waiting function and hook function runs in `condition-case', so
one failing does not keep the others from running."
  (when my/auto-commit--startup-pull-running
    (setq my/auto-commit--startup-pull-running nil)
    (when (timerp my/auto-commit--startup-pull-watchdog)
      (cancel-timer my/auto-commit--startup-pull-watchdog))
    (setq my/auto-commit--startup-pull-watchdog nil)
    (when lines
      (message "%s" (string-join lines "; ")))
    (let ((waiting my/auto-commit--startup-pull-waiting))
      (setq my/auto-commit--startup-pull-waiting nil)
      (dolist (function waiting)
        (condition-case err
            (funcall function)
          (error (message "After the start-up pull, %S failed: %s"
                          function (error-message-string err))))))
    (dolist (function my/auto-commit-pull-done-hook)
      (condition-case err
          (funcall function lines)
        (error (message "my/auto-commit-pull-done-hook: %S failed: %s"
                        function (error-message-string err)))))))

(defun my/auto-commit--startup-pull-next (dirs lines)
  "Pull the first of DIRS in the background, then the rest; LINES so far.
An error in one repository is logged and the next one pulled, so that
the chain always reaches `my/auto-commit--startup-pull-finish'."
  (if (null dirs)
      (my/auto-commit--startup-pull-finish (nreverse lines))
    (let ((dir (car dirs)))
      (condition-case err
          (if (not (file-directory-p (expand-file-name ".git" dir)))
              (my/auto-commit--startup-pull-next (cdr dirs) lines)
            (let ((before (my/auto-commit--head dir)))
              (my/auto-commit--pull-async
               dir
               (lambda (result)
                 (let ((line (condition-case nil
                                 (my/auto-commit--pull-line
                                  dir result
                                  (not (equal before (my/auto-commit--head dir))))
                               (error nil))))
                   (my/auto-commit--startup-pull-next
                    (cdr dirs) (if line (cons line lines) lines)))))))
        (error
         (my/auto-commit--log dir '("pull (start-up)") (error-message-string err) "error")
         (my/auto-commit--startup-pull-next (cdr dirs) lines))))))

(defun my/auto-commit--startup-pull ()
  "Start pulling every auto-committed repository in the background.
From `after-init-hook', when every module has added its repositories."
  (when (and my/auto-commit-pull (not my/auto-commit--startup-pull-running))
    (setq my/auto-commit--startup-pull-running (current-time))
    (setq my/auto-commit--startup-pull-watchdog
          (run-at-time my/auto-commit-startup-pull-wait nil
                       #'my/auto-commit--startup-pull-finish
                       (list "start-up pull still running, not waited for (C-c v l)")))
    (my/auto-commit--startup-pull-next
     (mapcar #'expand-file-name (my/auto-commit-directories)) nil)))

(add-hook 'after-init-hook #'my/auto-commit--startup-pull -90)

(defvar my/auto-commit--idle-timer nil
  "Repeating idle timer running `my/auto-commit-all'.")

(defun my/auto-commit--on-idle ()
  "Commit and push in the background, quietly, after a period of idleness.
Skipped while the start-up pull or another cycle runs; the next idle
period catches up.  Failures are shown as warnings, not swallowed."
  (unless (my/auto-commit--busy-in-background-p)
    (my/auto-commit--cycle #'ignore t)))

(defun my/auto-commit--arm-timer ()
  "Start the idle timer, replacing a running one.
Called at load and whenever `my/auto-commit-idle-seconds' changes."
  (when (timerp my/auto-commit--idle-timer)
    (cancel-timer my/auto-commit--idle-timer))
  (setq my/auto-commit--idle-timer
        (run-with-idle-timer my/auto-commit-idle-seconds t
                             #'my/auto-commit--on-idle)))

(my/auto-commit--arm-timer)

;; THE WAY OUT: ONE COMMIT, TWO ENTRANCES.  Until 2026-10-19 the exit
;; commit was wired three ways -- `kill-emacs-hook', the last frame in
;; `delete-frame-functions', and an advice before
;; `save-buffers-kill-emacs' -- with a flag against running twice.  Now:
;;
;;   C-x C-c and the like   `kill-emacs-query-functions': after the
;;                          buffers are saved, one cycle, then the
;;                          question when work is still only here
;;                          (`my/auto-commit--confirm-exit')
;;   anything else          `kill-emacs-hook' (shutdown, emacsclient -e
;;                          '(kill-emacs)'): the same cycle, no question
;;
;; Both go through `my/auto-commit-exit-commit', which runs once per
;; session.  The advice before `save-buffers-kill-emacs' existed so that
;; the notes were saved before "Save file ...?" could ask about them; it
;; now only saves (`my/auto-commit--save-before-quit'), no git.  The
;; frame handler could not fire outside a daemon (the sole frame cannot
;; be deleted), and in a daemon it set the once-only flag, so the real
;; exit later committed nothing.  In a daemon, closing the last client
;; frame now starts an ordinary background cycle instead.

(defvar my/auto-commit-done nil
  "Set once the exit commit has run, to prevent it running twice.")

(defun my/auto-commit-exit-commit ()
  "Commit and push once per session, on the way out, waiting for git.
Errors are logged in *Messages* and never stop Emacs from quitting.
Returns the descriptions of `my/auto-commit-all'."
  (unless my/auto-commit-done
    (setq my/auto-commit-done t)
    (condition-case err
        (my/auto-commit-all)
      (error (message "Exit commit failed: %s" (error-message-string err))
             nil))))

(define-obsolete-function-alias 'my/auto-commit-all-once
  #'my/auto-commit-exit-commit "2026-10-19")

(add-hook 'kill-emacs-hook #'my/auto-commit-exit-commit)

(defun my/auto-commit--save-before-quit (&rest _)
  "Save the buffers of auto-committed repositories before quitting asks.
So \"Save file ...?\" never asks about a note: its repository commits
it anyway.  No git here; the commit follows in
`my/auto-commit--confirm-exit' or `kill-emacs-hook'."
  (condition-case err
      (my/auto-commit--save-buffers)
    (error (message "Saving before quitting: %s" (error-message-string err)))))

(advice-add 'save-buffers-kill-emacs :before #'my/auto-commit--save-before-quit)

;; A commit message still open when quitting: git waits for it, so Emacs
;; asks about "active processes" and "other clients" (the message
;; buffer is one), and the commit is lost with the message.  Asked
;; first, before those questions, and the quit stops unless the answer
;; is to drop the commit.  (2026-10-22: a message buffer from C-c v c
;; left out of sight did exactly that.)
(defun my/auto-commit--message-before-quit (&rest _)
  "Stop quitting while a commit message is open, unless told to drop it."
  (let ((open (my/auto-commit--message-buffers)))
    (when (and open
               (not noninteractive)
               (not (yes-or-no-p
                     (format "A commit message is still open (%s); git waits for it.  Quit anyway, without that commit? "
                             (mapconcat #'buffer-name open ", ")))))
      (pop-to-buffer (car open))
      (user-error "Not quitting: finish the commit with C-c C-c or cancel it with C-c C-k, then quit"))))

(advice-add 'save-buffers-kill-emacs :before #'my/auto-commit--message-before-quit)

(defun my/auto-commit--on-last-client-frame (frame)
  "In a daemon, start a background cycle when FRAME is the last client frame.
Emacs keeps running, so this is not the exit commit: the real exit
later commits again."
  (when (and (daemonp)
             (frame-parameter frame 'client)
             (not (seq-some (lambda (other)
                              (and (not (eq other frame))
                                   (frame-parameter other 'client)))
                            (frame-list)))
             (not (my/auto-commit--busy-in-background-p)))
    (my/auto-commit--cycle #'ignore t)))

(add-hook 'delete-frame-functions #'my/auto-commit--on-last-client-frame)

;; The last word before quitting.  `kill-emacs-query-functions' run
;; after the buffers have been saved, so the cycle commits what the save
;; just wrote; a function returning nil cancels the quit.
(defun my/auto-commit--confirm-exit ()
  "Commit and push once more; ask before quitting if work is still only here.
The exit commit runs here for interactive quits, whether or not the
question is turned on (`my/auto-commit-confirm-exit')."
  (if noninteractive
      t
    (my/auto-commit-exit-commit)
    (if (not my/auto-commit-confirm-exit)
        t
      (let ((pending
             (delq nil (mapcar (lambda (dir)
                                 (let ((reason (condition-case nil
                                                   (my/auto-commit-pending dir)
                                                 (error nil))))
                                   ;; A folder kept from pushing on
                                   ;; purpose (a test copy) is not asked
                                   ;; about at every exit.
                                   (and reason
                                        (not (and (equal reason my/auto-commit--push-off-reason)
                                                  my/auto-commit-push))
                                        (format "%s (%s)"
                                                (abbreviate-file-name dir)
                                                reason))))
                               (my/auto-commit-directories)))))
        (or (null pending)
            (yes-or-no-p (format "Not on the server: %s.  Quit anyway? "
                                 (string-join pending "; ")))
            ;; Staying: the next quit commits again.  (Until 2026-10-19
            ;; the flag stayed set, and that later quit committed nothing.)
            (progn (setq my/auto-commit-done nil) nil))))))

(add-hook 'kill-emacs-query-functions #'my/auto-commit--confirm-exit)

;; ============================================================
;; MANUAL COMMIT FUNCTIONS
;; ============================================================

(defun my/commit-notes-now ()
  "Manually commit notes changes: stage every change, new files too, and
open the commit message buffer."
  (interactive)
  (let ((default-directory (expand-file-name my-notes-dir)))
    ;; `magit-stage-modified' with ALL is `git add --all .'.  Until
    ;; 2026-10-22 this called `magit-stage-all', which Magit does not
    ;; define: C-c v c stopped with "void-function" (found by the
    ;; weekly byte compilation, tests/weekly/compile.el).
    (magit-stage-modified t)
    (magit-commit-create)))

(defun my/commit-config-now ()
  "Manually commit config changes."
  (interactive)
  (let ((default-directory (expand-file-name user-emacs-directory)))
    (call-process "git" nil nil nil "add" "init.el" "modules/" ".gitignore")
    (magit-status-setup-buffer)))

;; ============================================================
;; GIT STATUS FUNCTIONS
;; ============================================================

(defun my/notes-git-status ()
  "Open Magit status for notes."
  (interactive)
  (let ((default-directory (expand-file-name my-notes-dir)))
    (magit-status-setup-buffer)))

(defun my/config-git-status ()
  "Open Magit status for config."
  (interactive)
  (let ((default-directory (expand-file-name user-emacs-directory)))
    (magit-status-setup-buffer)))

;; ============================================================
;; KEYBINDINGS
;; ============================================================

;; Notes
(global-set-key (kbd "C-c v s") 'my/notes-git-status)
(global-set-key (kbd "C-c v c") 'my/commit-notes-now)

;; Config
(global-set-key (kbd "C-c v S") 'my/config-git-status)
(global-set-key (kbd "C-c v C") 'my/commit-config-now)

;; Current file
(global-set-key (kbd "C-c v d") 'magit-diff-buffer-file)
(global-set-key (kbd "C-c v h") 'magit-log-buffer-file)

;; Auto-commit
(global-set-key (kbd "C-c v a") 'my/auto-commit-now)
(global-set-key (kbd "C-c v l") 'my/auto-commit-show-log)
(global-set-key (kbd "C-c v ?") 'my/auto-commit-status)

(provide '07-git)
;;; 07-git.el ends here
