;;; 01-ui.el --- Interface settings and session management -*- lexical-binding: t; -*-
;;; Commentary:
;; UI settings: menu bar, tabs, themes, desktop-save-mode
;; Session management: save/restore open files, window layouts, cursor positions
;; Completion: Vertico + Orderless for fuzzy matching

;;; Code:

;; ============================================================
;; BASIC UI SETTINGS
;; ============================================================

(setq inhibit-startup-screen t)

;; CHROME.  The tool bar and the scroll bar are the two elements that
;; date the frame most: a row of 16-pixel icons for commands this
;; configuration reaches through C-c n, and a scroll bar duplicating
;; information the mode line already gives as a percentage.  Neither is
;; ever clicked here, and both eat vertical and horizontal space that
;; the centred text column of 10-visual-fill.el then has to give back.
;;
;; The menu bar STAYS.  It is the only surface that lists what a mode
;; can do without knowing a key for it, which matters in a
;; configuration this large -- Org's own menu alone is a reference.
;; That is a different argument from the one against the tool bar, and
;; it comes out the other way.
;;
;; To revert either: change -1 to 1 here, or toggle for one session
;; with `M-x tool-bar-mode' / `M-x scroll-bar-mode'.
(tool-bar-mode -1)
(menu-bar-mode 1)
(scroll-bar-mode -1)

;; Set locale for Polish time/date formatting
(setq system-time-locale "pl_PL.UTF-8")

;; ============================================================
;; WINDOW SPLITTING: side by side, not stacked
;; ============================================================
;; Emacs splits a window when something asks to be displayed and no
;; suitable window exists.  Which way it splits is decided by
;; `split-window-sensibly', and its order is: BELOW first, right second.
;;
;;   1. split below, if the window is at least `split-height-threshold'
;;      lines tall  (default 80)
;;   2. split right, if it is at least `split-width-threshold' columns
;;      wide          (default 160)
;;   3. failing both, and only when the window is the frame's only one,
;;      split below regardless of the threshold
;;
;; On a full-screen frame step 1 always succeeds, so the second window
;; is always underneath -- for the whole life of the session, in every
;; context, no matter how wide the display is.  That is the behaviour
;; being changed here, and nothing in this configuration had ever
;; touched these two variables.
;;
;; A NOTE ON THE WORD "HORIZONTAL"
;; -------------------------------
;; Emacs names splits after the direction of the DIVIDING LINE, which
;; is the opposite of what most people mean.  `split-window-horizontally'
;; puts windows SIDE BY SIDE; `split-window-vertically' STACKS them.
;; The variables below avoid the word entirely, which is why they are
;; the reliable things to set.
;;
;; `split-height-threshold' nil means "never split below by choice".
;; Step 3 above is unaffected -- a frame too narrow for a side-by-side
;; split still gets a stacked one rather than nothing.
;;
;; 120 for the width: two 60-column windows is about the narrowest a
;; note stays readable at, and `my-fill-column' is 95, so a frame under
;; 120 columns has no business being split sideways anyway.

(setq split-height-threshold nil
      split-width-threshold 120)

;; Keep the two windows the same size after a split.  Without this a
;; side-by-side split can leave the new window noticeably narrower than
;; the one it came from, depending on what was displayed before.
(setq even-window-sizes t)

;; ------------------------------------------------------------
;; THE THRESHOLDS ONLY DECIDE HOW TO SPLIT, NOT WHETHER TO
;; ------------------------------------------------------------
;; `display-buffer' REUSES an existing window before it ever considers
;; making one.  So in a tab that already holds two windows, the two
;; variables above are never consulted: the buffer simply lands in
;; whichever window is not the current one, and if that window happens
;; to be below, everything keeps appearing below no matter what the
;; thresholds say.
;;
;; Worse, the layout persists.  `desktop-restore-frames' saves window
;; configurations along with the frameset, so a stacked layout created
;; once comes back on every start and keeps being reused -- which is
;; what "it has done this for months" looks like from the inside.
;;
;; `display-buffer-base-action' settles it by naming a DIRECTION rather
;; than a split.  `display-buffer-in-direction' with `right' reuses a
;; window on the right when there is one and creates one when there is
;; not, so the answer no longer depends on what the tab happened to
;; look like beforehand.
;;
;; TO BACK THIS OUT, comment out this form and keep the thresholds:
;; they are enough on their own as long as every tab starts from a
;; single window (`C-x 1').  This is the belt to their braces, and it
;; is a global default -- it applies to *Help*, compilation output and
;; everything else, not only to notes.

(setq display-buffer-base-action
      '((display-buffer-reuse-window
         display-buffer-in-direction)
        (direction . right)))

;; ============================================================
;; COMPLETION FRAMEWORK: Vertico + Orderless + Marginalia
;; ============================================================

;; Vertico: Better minibuffer (vertical completion)
(use-package vertico
  :ensure t
  :init
  (vertico-mode))

;; Orderless: Fuzzy matching (space-separated, out-of-order matching)
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Marginalia: Annotations in minibuffer (shows descriptions)
(use-package marginalia
  :ensure t
  :init
  (marginalia-mode))

;; ============================================================
;; CONSULT: load it, so the pieces built on it actually start
;; ============================================================
;; 04-denote.el declares consult-denote with `:after (denote consult)',
;; which defers its whole body until BOTH features are provided.
;; denote loads eagerly; consult did not, because nothing in the
;; configuration ever required it -- package.el installed it as a
;; dependency and left it on disk.  So `(consult-denote-mode 1)' did
;; not run at startup, and the Denote sources it adds to
;; `consult-buffer' were absent until some consult command happened to
;; load the package.  `consult-denote-grep' in the Find menu still
;; worked, via its own autoload; the integration around it did not.
;;
;; Requiring consult here fixes that at the source.  This module owns
;; the completion stack (vertico, orderless, marginalia), so it is
;; where the fourth piece belongs.
;;
;; BINDINGS ARE DELIBERATELY SPARSE.  The usual consult setup rebinds
;; C-s to `consult-line'; here C-s is `save-buffer' (02-editing.el, a
;; CUA-style choice this configuration makes throughout) and taking it
;; would break a reflex used hundreds of times a day.  C-x C-b is
;; ibuffer (02-editing.el).  What is left free and worth having:
;;
;;   C-x b    consult-buffer      -- buffers, recent files and the
;;                                   Denote sources in one prompt
;;   M-g g    consult-goto-line   -- with a live preview of the line
;;   M-g i    consult-imenu       -- headings in the current note
;;   M-s l    consult-line        -- search in buffer, with preview
;;
;; To search across notes, keep using `consult-denote-grep' (C-c n f g).

(use-package consult
  :ensure t
  :demand t
  :bind (("C-x b"   . consult-buffer)
         ("M-g g"   . consult-goto-line)
         ("M-g M-g" . consult-goto-line)
         ("M-g i"   . consult-imenu)
         ("M-s l"   . consult-line))
  :config
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  ;; Preview on demand: nothing is previewed until `M-.' is pressed on
  ;; a candidate.
  ;;
  ;; The sources include note files, so an automatic preview opens a
  ;; buffer per candidate while scrolling a long list -- and each of
  ;; those runs the full `org-mode-hook': visual-fill-column,
  ;; prettify-symbols, org-modern, the per-silo font setup.  A debounce
  ;; makes that cheaper without making it deliberate; asking for the
  ;; preview makes it deliberate, which is what a list of 3700 notes
  ;; wants.
  ;;
  ;; For an automatic preview after a pause instead, use
  ;; `(:debounce 0.5 any)'; for one on every candidate, `any'.
  (setq consult-preview-key "M-."))

;; Enable completion-read-multiple with comma separator
(setq crm-separator ",")

;; ============================================================
;; DESKTOP-SAVE-MODE: Session persistence
;; ============================================================
;; Saves open files and cursor positions between sessions.
;;
;; 3-LAYER STRATEGY
;; ----------------
;; 1. TRIM (before save)  : keep only the `my/desktop-max-buffers' (10)
;;                          most-recently-USED file buffers in the
;;                          desktop file.  Prevents the list from
;;                          growing indefinitely.
;;                          "Used" means Emacs's own recency: the order
;;                          of `buffer-list', where a buffer moves to
;;                          the front every time it is selected.  This
;;                          deliberately replaced the earlier sort by
;;                          file modification time on disk, which would
;;                          kill buffers you had been reading (but not
;;                          editing) all day, while keeping files that
;;                          some external process happened to touch.
;; 2. EAGER (on restore)  : restore up to `desktop-restore-eager' (10)
;;                          buffers synchronously so the UI appears
;;                          fast regardless of list size.
;; 3. LAZY (background)   : restore remaining buffers during idle time.
;;                          NOTE: with the trim limit (10) now equal to
;;                          the eager limit (10), everything restores
;;                          eagerly and this layer is effectively
;;                          dormant.  It is kept so that raising
;;                          `my/desktop-max-buffers' later re-activates
;;                          lazy loading with no other changes.

(defgroup my/desktop nil
  "Custom desktop-save buffer trimming."
  :group 'convenience)

(defconst my/desktop-max-buffers 10
  "Maximum number of file buffers to persist in the desktop file.
Buffers beyond this count (in most-recently-used order) are killed
by `my/desktop-trim-buffers' just before the desktop is saved.
Buffers protected by `my/desktop--protected-buffers' (open in a
tab, or manually pinned) do not count toward this limit at all.")

(defvar-local my/desktop-keep-buffer nil
  "Non-nil means this buffer is exempt from `my/desktop-trim-buffers'.
Toggle interactively with `my/desktop-toggle-keep-buffer', or set it
permanently for a file via a file-local variable, e.g.:

;; Local Variables:
;; my/desktop-keep-buffer: t
;; End:

A pin (📌) appears in the mode line for any buffer where this is set.")
(put 'my/desktop-keep-buffer 'safe-local-variable #'booleanp)

(defun my/desktop-toggle-keep-buffer ()
  "Toggle whether the current buffer is pinned against desktop trimming.
Pinned buffers are never killed by `my/desktop-trim-buffers', regardless
of how long ago they were last used."
  (interactive)
  (setq my/desktop-keep-buffer (not my/desktop-keep-buffer))
  (force-mode-line-update)
  (message "Buffer %s %s"
           (buffer-name)
           (if my/desktop-keep-buffer
               "pinned (protected from desktop trim)"
             "unpinned (subject to desktop trim again)")))

(defvar my/desktop-keep-buffer-mode-line
  '(:eval (when my/desktop-keep-buffer
            (propertize " 📌" 'face 'warning
                        'help-echo "Pinned: protected from desktop-trim")))
  "Mode-line construct showing a pin for `my/desktop-keep-buffer' buffers.")
(put 'my/desktop-keep-buffer-mode-line 'risky-local-variable t)
(unless (memq 'my/desktop-keep-buffer-mode-line mode-line-misc-info)
  (add-to-list 'mode-line-misc-info 'my/desktop-keep-buffer-mode-line))

(defcustom my/desktop-tab-protect-depth 3
  "How many of each tab's most-recently-used buffers stay protected.
Applies per tab: a buffer only needs to be among this many recently
used buffers in *some* tab to be exempt from `my/desktop-trim-buffers'.

This is deliberately small and per-tab, not \"every buffer ever opened
in that tab\": `frame-parameter's buffer-list' (aka a tab's `wc-bl') is
Emacs's own most-recently-used list, and it only grows over a tab's
lifetime -- it never forgets a buffer just because you moved on to
something else in that tab.  Protecting the full list would mean a
tab you've had open for a month protects hundreds of stale buffers.
Taking only the front N keeps the protected set bounded no matter how
old the tab is, while still covering what you're actually looking at
in it (the front of an MRU list is always the most recent buffer)."
  :type 'integer
  :group 'my/desktop)

(defun my/desktop--tab-buffers ()
  "Return the small set of buffers considered \"open\" in tab-bar tabs.
For the current tab: buffers actually shown in a window right now,
plus the front of its buffer-list for the same MRU-depth reason as
below.  For every other tab: the `my/desktop-tab-protect-depth' most
recently used buffers in that tab, taken from the front of its own
`wc-bl' (which `tab-bar' restores into `buffer-list' whenever you
switch to that tab -- see `tab-bar--tab' in tab-bar.el).  Deliberately
does NOT use the full `wc-bl'/`wc-bbl' history or the buried-buffer
list: those grow without bound over a tab's lifetime and would
eventually protect buffers you haven't looked at in months."
  (let (bufs)
    (dolist (win (window-list nil 'no-minibuf))
      (push (window-buffer win) bufs))
    (setq bufs (append bufs
                        (seq-take (frame-parameter nil 'buffer-list)
                                  my/desktop-tab-protect-depth)))
    (when (bound-and-true-p tab-bar-mode)
      (dolist (tab (funcall tab-bar-tabs-function))
        (unless (eq (car tab) 'current-tab)
          (setq bufs (append bufs
                              (seq-take (cdr (assq 'wc-bl tab))
                                        my/desktop-tab-protect-depth))))))
    (seq-filter #'buffer-live-p (delete-dups bufs))))

(defcustom my/desktop-always-keep-regexps
  (list (regexp-quote "function_helper.org"))
  "File name regexps whose buffers are never trimmed.

The pin (`my/desktop-toggle-keep-buffer', \\[my/desktop-toggle-keep-buffer])
protects one buffer for one session and has to be remembered.  This
list protects files permanently and without any action: a reference
document consulted every day but rarely edited will otherwise keep
falling out of the most-recently-used window and being killed, which
is the exact failure mode of a pure MRU policy.

Matched against the full file name, so a whole silo can be protected
with something like (regexp-quote my-notes-journal)."
  :type '(repeat regexp)
  :group 'my/desktop)

(defun my/desktop--always-keep-p (buffer)
  "Return non-nil when BUFFER's file matches `my/desktop-always-keep-regexps'."
  (when-let* ((file (buffer-file-name buffer)))
    (seq-some (lambda (re) (string-match-p re file))
              my/desktop-always-keep-regexps)))

(defun my/desktop--transient-buffer-p (buffer)
  "Return non-nil when BUFFER must not be killed by the trim.

Three kinds, and each of them has bitten or would bite:

MODIFIED buffers.  `kill-buffer\=' on an unsaved file buffer asks
\"Buffer modified; kill anyway?\", and the trim runs from the
`desktop-auto-save\=' timer, where a prompt is either a modal
interruption in the middle of typing or, worse, silently answered.  A
buffer with unsaved changes is also by definition one being worked on.

Buffers under a `.git\=' DIRECTORY.  COMMIT_EDITMSG, MERGE_MSG,
rebase todo lists: transient files that a version-control command owns
for the length of one operation.  They are ordinary file-visiting
buffers, so nothing else here excluded them.

Buffers that have installed their own `kill-buffer-query-functions\='.
That is a buffer stating in the only way Emacs provides that it is not
ready to die -- with-editor does exactly this for COMMIT_EDITMSG, and
the check generalises to anything else that adopts the convention."
  (or (buffer-modified-p buffer)
      (when-let* ((file (buffer-file-name buffer)))
        (string-match-p "/\\.git/" file))
      (local-variable-p 'kill-buffer-query-functions buffer)))

(defun my/desktop--protected-buffers ()
  "Buffers `my/desktop-trim-buffers' must never kill."
  (delete-dups
   (append (my/desktop--tab-buffers)
           (seq-filter (lambda (buf)
                         (buffer-local-value 'my/desktop-keep-buffer buf))
                       (buffer-list))
           (seq-filter #'my/desktop--always-keep-p (buffer-list)))))

(defun my/desktop--classify-buffers ()
  "Classify file buffers by what will happen to them at the next save.

Returns a plist with :pinned, :tabs, :always (the three protected
groups, which may overlap), :survivors (kept because they are recent
enough) and :doomed (to be killed).

Both `my/desktop-trim-buffers' and `my/desktop-show-protected' read
this, so what the report shows and what the trim does cannot drift
apart -- a report that disagrees with the behaviour would be worse
than no report at all."
  (let* ((protected (my/desktop--protected-buffers))
         (candidates
          (seq-filter
           (lambda (buf)
             (and (buffer-file-name buf)
                  (not (memq buf protected))
                  (not (my/desktop--transient-buffer-p buf))
                  (not (memq (buffer-local-value 'major-mode buf)
                             desktop-modes-not-to-save))
                  (not (string-match-p desktop-files-not-to-save
                                       (buffer-file-name buf)))))
           ;; Already sorted: most recently used first.
           (buffer-list))))
    (list :pinned    (seq-filter (lambda (b)
                                   (buffer-local-value 'my/desktop-keep-buffer b))
                                 (buffer-list))
          :tabs      (seq-filter #'buffer-file-name (my/desktop--tab-buffers))
          :always    (seq-filter #'my/desktop--always-keep-p (buffer-list))
          :survivors (seq-take candidates my/desktop-max-buffers)
          :doomed    (nthcdr my/desktop-max-buffers candidates))))

(defun my/desktop-show-protected ()
  "Report which note buffers survive the next desktop save, and why.

Answers the question the trim otherwise leaves implicit: of everything
currently open, what comes back after a restart?  Buffers can appear
in more than one protected group; any one of them is enough."
  (interactive)
  (let* ((info (my/desktop--classify-buffers))
         (fmt (lambda (buffers)
                (if buffers
                    (mapconcat (lambda (b) (concat "    " (buffer-name b)))
                               buffers "\n")
                  "    (none)"))))
    (with-output-to-temp-buffer "*Desktop Survival*"
      (princ (format "Buffers surviving the next desktop save\n\
=======================================\n\
Trim limit: %d most recently used, protected buffers excluded.\n\n\
PINNED  (C-c d k, shown as a pin in the mode line)\n%s\n\n\
OPEN IN A TAB  (top %d most recent per tab)\n%s\n\n\
ALWAYS KEPT  (my/desktop-always-keep-regexps)\n%s\n\n\
RECENT ENOUGH  (within the trim limit)\n%s\n\n\
WILL BE KILLED AT THE NEXT SAVE\n%s\n"
                     my/desktop-max-buffers
                     (funcall fmt (plist-get info :pinned))
                     my/desktop-tab-protect-depth
                     (funcall fmt (plist-get info :tabs))
                     (funcall fmt (plist-get info :always))
                     (funcall fmt (plist-get info :survivors))
                     (funcall fmt (plist-get info :doomed)))))))

(defun my/desktop-trim-buffers ()
  "Before saving desktop, kill buffers beyond `my/desktop-max-buffers'.
Keeps the N most recently USED file-visiting buffers and kills the
rest, so they are not written into the desktop file.  Buffers that are
open in any tab, manually pinned via `my/desktop-keep-buffer', or
matching `my/desktop-always-keep-regexps' are excluded from
consideration entirely: they are never killed here and never count
toward the N-buffer limit.

Recency comes for free from `buffer-list', which returns buffers in
most-recently-selected order (`seq-filter' preserves that order), so
no explicit sorting is needed.  Buffers whose major mode is listed in
`desktop-modes-not-to-save' or whose file matches
`desktop-files-not-to-save' are ignored entirely: desktop would not
persist them anyway, so they neither count toward the limit nor get
killed here.

Use \\[my/desktop-show-protected] to see the outcome before it happens."
  (let ((to-kill (plist-get (my/desktop--classify-buffers) :doomed))
        (refused 0))
    (when to-kill
      (message "desktop trim: killing %d old buffers before save"
               (length to-kill))
      (dolist (buf to-kill)
        ;; A buffer is allowed to refuse.  Entries in
        ;; `kill-buffer-query-functions' may signal rather than return
        ;; nil -- with-editor does, for one -- and this hook runs from
        ;; the `desktop-auto-save' timer, where an unhandled signal
        ;; aborts the whole of `desktop-save':
        ;; the session is then not written at all because one buffer
        ;; declined to die.  Losing the session to a refused kill is a
        ;; far worse outcome than keeping one extra buffer, so each kill
        ;; is attempted on its own and a refusal is counted, not raised.
        (condition-case err
            (kill-buffer buf)
          (error
           (setq refused (1+ refused))
           (message "desktop trim: kept %s (%s)"
                    (buffer-name buf) (error-message-string err)))))
      (when (> refused 0)
        (message "desktop trim: %d buffer(s) declined to be killed"
                 refused)))))

(defun my/restore-chrome-preferences ()
  "Re-apply chrome settings that a desktop frameset restore overrode.
Run from `desktop-after-read-hook'; a no-op when the modes are already
off, so it is safe to call at any time."
  (tool-bar-mode -1)
  (scroll-bar-mode -1))

(use-package desktop
  :ensure nil
  :init
  (setq desktop-dirname             "~/.emacs.d/desktop/"
        desktop-base-file-name      "desktop"
        desktop-base-lock-name      "desktop.lock"
        desktop-path               (list desktop-dirname)
        desktop-save               t
        ;; `check-pid' rather than t.
        ;;
        ;; desktop.el writes a lock file naming the PID that owns the
        ;; session.  With t, a locked desktop is LOADED without asking
        ;; -- but on exit `desktop-save' still finds the lock held by
        ;; another PID and declines to overwrite it.  A session that
        ;; died without releasing its lock (a crash, a kill -9, an init
        ;; that errored badly enough to be killed) therefore leaves
        ;; every later session reading the same frozen state and
        ;; writing nothing back: new tabs open, and are gone after a
        ;; restart.
        ;;
        ;; `check-pid' loads the desktop when the owning process is no
        ;; longer running, and takes ownership, so the next save
        ;; succeeds.  A genuinely concurrent second Emacs is still
        ;; refused, which is the case the lock exists for.
        desktop-load-locked-desktop 'check-pid
        ;; Layer 2: only 10 buffers block startup, rest load in background
        desktop-restore-eager      10)
  :config
  (unless (file-exists-p desktop-dirname)
    (make-directory desktop-dirname t))
  (add-to-list 'desktop-modes-not-to-save 'pdf-view-mode)
  (add-to-list 'desktop-modes-not-to-save 'nov-mode)
  ;; Layer 1: trim buffer list before every save
  (add-hook 'desktop-save-hook #'my/desktop-trim-buffers)

  ;; CHROME SURVIVES A DESKTOP RESTORE, AND HAS TO BE PUT BACK
  ;; --------------------------------------------------------
  ;; `desktop-restore-frames' is t by default, and the frameset it
  ;; saves includes `tool-bar-lines' and `vertical-scroll-bars'.
  ;; Restoring the frameset therefore re-applies whatever those were
  ;; when the desktop was last saved -- which, for a desktop written
  ;; before the tool bar was turned off, means the tool bar comes back
  ;; on every start and `(tool-bar-mode -1)' at the top of this file
  ;; appears to do nothing.  Frameset restore overrides
  ;; `default-frame-alist' too, so setting the parameters there is not
  ;; a fix either.
  ;;
  ;; Re-asserting after the restore is.  `my/restore-chrome-preferences'
  ;; is defined at top level below, not here, so that the pre-commit
  ;; grep for duplicate top-level definitions can see it.
  (add-hook 'desktop-after-read-hook #'my/restore-chrome-preferences)

  (desktop-save-mode 1))

;; ============================================================
;; SAVING THE SESSION BY HAND, AND SEEING WHY IT FAILED
;; ============================================================
;; `desktop-save-mode' writes the session from `kill-emacs-hook', where
;; a failure is close to invisible: the message scrolls past as the
;; frame disappears, and the next start quietly restores whatever was
;; last written successfully.  This command runs the same save with
;; errors reported, which turns "the session is not being saved" from a
;; guess into a one-line answer.

(defun my/desktop-force-save ()
  "Save the desktop now, reporting success or the reason for failure.
Takes over the lock if the owning process is gone."
  (interactive)
  (condition-case err
      (progn
        (desktop-save desktop-dirname t)
        (message "Desktop saved to %s (%d file buffers, %d tabs)"
                 desktop-dirname
                 (length (seq-filter #'buffer-file-name (buffer-list)))
                 (length (tab-bar-tabs))))
    (error (message "Desktop save FAILED: %s" (error-message-string err)))))

(defun my/desktop-status ()
  "Report who owns the desktop lock and when the desktop was last written."
  (interactive)
  (let* ((file  (expand-file-name desktop-base-file-name desktop-dirname))
         (owner (ignore-errors (desktop-owner desktop-dirname))))
    (message "Desktop: %s | last written %s | lock owner %s (this Emacs is %d)"
             (if (file-exists-p file) "present" "MISSING")
             (if (file-exists-p file)
                 (format-time-string "%F %T"
                                     (file-attribute-modification-time
                                      (file-attributes file)))
               "-")
             (or owner "none")
             (emacs-pid))))

;; ============================================================
;; STARTUP: one hook, one firing
;; ============================================================
;; Several modules need to run something once the session is up: the
;; dashboard opens itself (15-workspace.el), spell checking is unblocked
;; (03-spelling.el).  Getting that moment right is fiddly and it was
;; being solved twice, in modules that had no business knowing about
;; desktop restoration:
;;
;;   - `desktop-after-read-hook' fires when a session was restored, and
;;     never fires when there was no desktop file to read;
;;   - `emacs-startup-hook' fires either way, but too early relative to
;;     restoration.
;;
;; Both paths converge here, a guard makes sure only the first one
;; counts, and consumers add themselves to one ordinary hook without
;; needing to know which path was taken.  This module owns the session,
;; so it is the one that can say when the session is ready; it does not
;; need to know what anyone does with that fact.
;;
;; The delay lets the rest of startup settle before anything reshapes
;; windows.

(defcustom my/desktop-startup-delay 0.5
  "Seconds to wait after startup before running `my/desktop-after-startup-hook'."
  :type 'number :group 'my/desktop)

(defvar my/desktop-after-startup-hook nil
  "Hook run once, shortly after Emacs has finished starting up.

Runs whether or not a desktop session was restored, and runs exactly
once per Emacs process.  Add to it from any module that needs to act on
a session that is ready to use.")

(defvar my/desktop--startup-done nil
  "Non-nil once `my/desktop-after-startup-hook' has been run.")

(defun my/desktop--run-startup-hook ()
  "Run `my/desktop-after-startup-hook' once, after a short delay."
  (unless my/desktop--startup-done
    (setq my/desktop--startup-done t)
    (run-with-timer my/desktop-startup-delay nil
                    (lambda () (run-hooks 'my/desktop-after-startup-hook)))))

(add-hook 'desktop-after-read-hook #'my/desktop--run-startup-hook)
(add-hook 'emacs-startup-hook #'my/desktop--run-startup-hook 90)

;; Don't save temporary/auxiliary files
(add-to-list 'desktop-modes-not-to-save 'fundamental-mode)
;; The "/.git/" branch covers COMMIT_EDITMSG, MERGE_MSG and rebase todo files.
;; Restoring one of those into a later session is meaningless -- the
;; operation that created it finished long ago -- and it is the same set
;; the trim now refuses to kill, so the two policies agree.
(setq desktop-files-not-to-save
      (concat desktop-files-not-to-save
              "\\|/\\.git/"
              "\\|\\(\\.aux\\|\\.log\\|\\.out\\|\\.toc\\|\\.tex\\|\\.epub\\)$"))

;; Manual save command
(defun my/desktop-save-now ()
  "Save desktop session immediately."
  (interactive)
  (desktop-save desktop-dirname)
  (message "Desktop saved!"))

(global-set-key (kbd "C-c d s") 'my/desktop-save-now)
(global-set-key (kbd "C-c d k") 'my/desktop-toggle-keep-buffer)
(global-set-key (kbd "C-c d p") 'my/desktop-show-protected)

;; ============================================================
;; RESTORE THE DASHBOARD AFTER A SESSION IS RESTORED
;; ============================================================
;; `desktop-save' only persists file-visiting buffers.  The dashboard
;; is generated text with no file behind it, so it is never saved and
;; never comes back -- the Dashboard tab returns from the restored
;; frame configuration, but its window points at a buffer that no
;; longer exists.  Rebuilding it at startup is both cheap and exact,
;; since the content is derived from the notes on disk anyway.

(defcustom my/desktop-open-dashboard-at-startup t
  "Whether to rebuild and show the Notes Dashboard after startup.
The dashboard is not persisted by `desktop-save' because it visits no
file; it is regenerated instead."
  :type 'boolean
  :group 'my/desktop)

(defun my/desktop--open-dashboard-at-startup ()
  "Rebuild the Notes Dashboard once startup has finished.
Guarded with `fboundp' because the dashboard lives in 15-workspace.el,
which loads after this file."
  (when (and my/desktop-open-dashboard-at-startup
             (fboundp 'my/open-notes-dashboard))
    (my/open-notes-dashboard)))

(add-hook 'emacs-startup-hook #'my/desktop--open-dashboard-at-startup 90)

;; ============================================================
;; SAVE-PLACE-MODE: Remember cursor position
;; ============================================================

(use-package saveplace
  :ensure nil
  :init
  (save-place-mode 1)
  :config
  (setq save-place-file "~/.emacs.d/saveplace"))

;; ============================================================
;; TAB-BAR-MODE: Workspace tabs (like browser tabs)
;; ============================================================

;; ============================================================
;; FIXED TABS: one named tab per recurring activity
;; ============================================================
;; Shared helper for commands that should always run in their own
;; named tab (Dashboard, Journal, History, ...).  Three places used to
;; carry their own copy of this logic; they now all call this.
;;
;; Note what this deliberately does NOT use.  The declarative route
;; would be `display-buffer-alist' with the `display-buffer-in-tab'
;; action, and for plain buffer display that is the better tool.  It
;; does not fit here because these commands do more than display a
;; buffer: `my/denote-journal' finds a file, moves point to the end,
;; and inserts a timestamped heading.  Routing only the *display* would
;; leave the editing to happen wherever point already was.  Switching
;; tab first and then running the command puts the whole command in the
;; right place, and needs no global change to
;; `switch-to-buffer-obey-display-actions'.

(defun my/fixed-tab-goto (name)
  "Switch to the tab called NAME, creating it if it does not exist.
A new tab is created immediately to the right of the current one, so
tabs accumulate in the order activities are first opened rather than
jumping to the front.  Returns non-nil when the tab had to be created.

`tab-bar-new-tab-to' is bound explicitly rather than relying on its
global value, so this placement holds even if that option is
customized elsewhere."
  (if (seq-find (lambda (tab) (equal (alist-get 'name tab) name))
                (tab-bar-tabs))
      (progn
        ;; Switching to the tab that is already current is a no-op
        ;; worth skipping: it would still push a redundant entry onto
        ;; the tab switching history.
        (unless (equal (alist-get 'name (tab-bar--current-tab)) name)
          (tab-bar-switch-to-tab name))
        nil)
    (let ((tab-bar-new-tab-to 'right))
      (tab-bar-new-tab))
    (tab-bar-rename-tab name)
    t))

(use-package tab-bar
  :ensure nil
  :init
  (tab-bar-mode 1)
  :bind (("C-c t n" . tab-bar-new-tab)
         ("C-c t c" . tab-bar-close-tab)
         ("C-c t o" . tab-bar-switch-to-tab)
         ("C-c t r" . tab-bar-rename-tab))
  :config
  (setq tab-bar-show t)
  (setq tab-bar-new-tab-choice "*scratch*")
  (setq tab-bar-close-button-show t))

;; ============================================================
;; WINNER-MODE: Undo/redo window configurations
;; ============================================================

(use-package winner
  :ensure nil
  :init
  (winner-mode 1)
  :bind (("C-c <left>"  . winner-undo)
         ("C-c <right>" . winner-redo)))

;; ============================================================
;; ORG-MODE VISUAL SETTINGS
;; ============================================================

;; visual-line-mode and fill-column variable for org files.
;; NOTE: visual-line-mode hook is owned by 02-editing.el.
;; display-fill-column-indicator-mode is owned by 10-visual-fill.el.
(add-hook 'org-mode-hook
          (lambda ()
            (setq fill-column my-fill-column)))

;; Face definitions for org-quote, org-block etc. live exclusively in
;; custom.el (managed by Customize).  Do NOT add custom-set-faces calls
;; here — duplicate definitions cause nil-attribute merge warnings.
(setq org-fontify-quote-and-verse-blocks t)

;; Replace block markers with Unicode symbols
(setq-default prettify-symbols-alist
              '(("#+BEGIN_QUOTE" . "\U0001F4AC")
                ("#+END_QUOTE" . "\U0001F4AC")
                ("#+begin_quote" . "\U0001F4AC")
                ("#+end_quote" . "\U0001F4AC")
                ("#+BEGIN_SRC" . "\u03BB")
                ("#+END_SRC" . "\u03BB")
                ("#+begin_src" . "\u03BB")
                ("#+end_src" . "\u03BB")))

(setq prettify-symbols-unprettify-at-point 'right-edge)
(add-hook 'org-mode-hook 'prettify-symbols-mode)

;; ============================================================
;; WORD COUNT IN MODELINE
;; ============================================================

(defface my/modeline-word-count
  '((t :inherit (bold shadow)))
  "Face for the word count segment of the mode line.
Inherits rather than naming a colour, so the segment follows the
active theme through a light/dark toggle.  The previous literal
\"purple\" was legible on the light theme only."
  :group 'mode-line-faces)

(defun my/word-count-modeline ()
  "Display word count in modeline for text modes."
  (when (derived-mode-p 'org-mode 'text-mode)
    (let ((words (count-words (point-min) (point-max))))
      (propertize (format "%d " words) 'face 'my/modeline-word-count))))

;; ============================================================
;; THE MODE LINE: ONE DEFINITION, HERE
;; ============================================================
;; This `setq-default' is the only one in the configuration.  There
;; used to be a second, identical but for one extra segment, at the top
;; of 13-centered-writing.el -- so whichever file loaded last silently
;; decided the mode line, and editing this one had no effect.
;;
;; Other modules contribute segments through `mode-line-misc-info',
;; which is the mechanism `my/desktop-keep-buffer-mode-line' above
;; already uses and which 13-centered-writing.el now uses too.  A
;; module that adds a segment that way can be deleted without leaving
;; the mode line broken, and does not need to know what the format
;; looks like.

(setq-default mode-line-format
              '((:eval (my/word-count-modeline))
                "%e"
                mode-line-front-space
                mode-line-mule-info
                mode-line-client
                mode-line-modified
                mode-line-remote
                mode-line-frame-identification
                mode-line-buffer-identification
                "   "
                mode-line-position
                (vc-mode vc-mode)
                "  "
                mode-line-modes
                mode-line-misc-info
                mode-line-end-spaces))

;; ============================================================
;; HELPER FUNCTIONS
;; ============================================================

(defun open-init-el-bottom-split ()
  "Open init.el in bottom window split."
  (interactive)
  (let ((init-file (expand-file-name "~/.emacs.d/init.el")))
    (split-window-below)
    (other-window 1)
    (find-file init-file)))

;; Auto-close auxiliary files (LaTeX exports, etc.)
(defun my/kill-auxiliary-buffers (&rest _args)
  "Kill auxiliary file buffers (.aux, .log, .tex, etc.)."
  (interactive)
  (dolist (buf (buffer-list))
    (let ((name (buffer-file-name buf)))
      (when (and name
                 (or (string-suffix-p ".aux" name)
                     (string-suffix-p ".log" name)
                     (string-suffix-p ".out" name)
                     (string-suffix-p ".toc" name)
                     (string-suffix-p ".tex" name)))
        (kill-buffer buf)))))

(add-hook 'emacs-startup-hook 'my/kill-auxiliary-buffers)
(add-hook 'org-export-before-processing-hook 'my/kill-auxiliary-buffers)

(provide '01-ui)
;;; 01-ui.el ends here
