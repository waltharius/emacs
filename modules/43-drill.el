;;; 43-drill.el --- Spaced repetition with org-drill -*- lexical-binding: t; -*-
;;; Commentary:
;; Flashcards kept in ordinary Denote notes, reviewed with org-drill.
;;
;;   C-c n r   the menu
;;
;; WHAT A CARD IS HERE.  org-drill's simple card: a heading tagged
;; `drill', the question as its body, the answer in a subheading that
;; stays hidden until asked for.
;;
;;   **** Karta :drill:
;;   Question text.
;;
;;   ***** Odpowiedź
;;   Answer text.
;;
;; The heading title is deliberately neutral.  org-drill shows it while
;; the answer is hidden, so a title that names the topic gives the
;; answer away.
;;
;; WHERE CARDS LIVE.  In notes whose file name carries the Denote keyword
;; `my/drill-keyword'.  The keyword, not a directory, is what makes a
;; note a card deck: decks can then sit in whichever silo suits them, and
;; the set is derived from the file names every time rather than stored
;; in a list that drifts -- the same rule as hub membership in
;; 33-denote-hubs.el.
;;
;; WHAT ORG-DRILL WRITES INTO THE NOTES.  Reviewing a card adds an `:ID:'
;; and a `SCHEDULED' date to its heading and DRILL_* properties to its
;; drawer.  The first session over many cards is slow once, while the
;; IDs are created.  The SCHEDULED dates matter for the agenda: card
;; decks must not be added to `org-agenda-files' (owned by 37-tasks.el),
;; or every card turns up in the agenda as a scheduled item.
;;
;; SAVING.  org-drill's own end-of-session behaviour is a
;; `save-some-buffers' prompt.  It is switched off; every session started
;; from this module saves the card buffers it touched when it ends --
;; including when it is quit or interrupted -- and reports how many.  An
;; unsaved session is lost scheduling data, and the idle auto-commit in
;; 07-git.el would otherwise be the only thing standing between the two.
;;
;; RELATION TO OTHER MODULES
;; - 04-denote.el (required in practice): `denote-directory-files' and
;;   `denote-extract-keywords-from-path' find the decks.  Without Denote
;;   the all-decks commands report why and do nothing; the buffer and
;;   subtree sessions still work.
;; - 12-transient.el, via `my/transient-append'.  Without it the commands
;;   remain available through M-x.
;; - 37-tasks.el is not used, but see above about `org-agenda-files'.
;;
;; Docs: ~/.emacs.d/function_helper.org::#drill

;;; Code:

(require 'org)
(require 'seq)
(require 'subr-x)
(require 'transient)

(declare-function org-drill "org-drill" (&optional scope drill-match resume-p cram))
(declare-function org-drill-cram "org-drill" (&optional scope drill-match))
(declare-function org-drill-tree "org-drill" ())
(declare-function org-drill-resume "org-drill" ())
(declare-function denote-directory-files "denote"
                  (&optional files-matching-regexp omit-current text-only
                             exclude-regexp has-identifier))
(declare-function denote-extract-keywords-from-path "denote" (path))

(defvar org-drill-question-tag)
(defvar org-drill-save-buffers-after-drill-sessions-p)
(defvar org-drill-add-random-noise-to-intervals-p)
(defvar org-drill-leech-method)
(defvar package-pinned-packages)
(defvar package-archives)
(defvar denote-known-keywords)

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/drill nil
  "Spaced repetition on top of org-drill."
  :group 'org)

(defcustom my/drill-keyword "karty"
  "Denote keyword that marks a note as a card deck.
Matched against the `__keyword' component of the file name."
  :type 'string
  :group 'my/drill)

(defcustom my/drill-card-title "Karta"
  "Heading title given to a card inserted by `my/drill-insert-card'.
Kept neutral on purpose: org-drill displays the title while the answer
is hidden."
  :type 'string
  :group 'my/drill)

(defcustom my/drill-answer-heading "Odpowiedź"
  "Title of the subheading that holds a card's answer.
org-drill does not read the title; it hides every subheading of a card.
The name only has to be recognisable when a deck is read as a note."
  :type 'string
  :group 'my/drill)

;; ============================================================
;; PACKAGE
;; ============================================================
;; org-drill 2.7.0 is on NonGNU ELPA, which Emacs 28 and later carry in
;; the default `package-archives'.  It is pinned there when that archive
;; is present, because MELPA's date-based version numbers always look
;; newer and would otherwise win: the stable release is the one wanted,
;; for the same reason as Denote.
;;
;; NOT `:pin nongnu'.  `use-package' signals when a pinned archive is
;; missing from `package-archives', and an error here aborts init.el --
;; the NOERROR argument of `load' covers a missing file, not a failing
;; one.  Adding to `package-pinned-packages' conditionally gives the same
;; result without that failure mode.
;;
;; SETTINGS GO IN `:config', NOT `:custom'.  `:custom' loads the library
;; to apply them, which would defeat `:defer'.  Three are changed:
;;
;;   save-buffers  nil   Replaced by the silent save in `my/drill--run'.
;;   random noise  t     Cards added in bulk share a creation day, and
;;                       without noise they keep coming due on the same
;;                       days.  The jitter scales with the interval, so
;;                       short intervals are barely affected.
;;   leech method  warn  The default, `skip', silently removes cards
;;                       that keep failing from every session.  Those
;;                       are the ones that most need work before an
;;                       exam, so they stay in and are flagged instead.
;;
;; The algorithm (SM5), session limits (30 items, 20 minutes) and every
;; other option keep org-drill's defaults.

(when (and (boundp 'package-archives)
           (assoc "nongnu" package-archives)
           (boundp 'package-pinned-packages))
  (add-to-list 'package-pinned-packages '(org-drill . "nongnu")))

(use-package org-drill
  :defer t
  :commands (org-drill org-drill-cram org-drill-tree org-drill-resume)
  :config
  (setq org-drill-save-buffers-after-drill-sessions-p nil)
  (setq org-drill-add-random-noise-to-intervals-p t)
  (setq org-drill-leech-method 'warn))

;; Register the keyword so it completes in `denote-rename-file-keywords'
;; before the first deck exists, as 33-denote-hubs.el does for hubs.
(with-eval-after-load 'denote
  (add-to-list 'denote-known-keywords my/drill-keyword))

;; ============================================================
;; FINDING DECKS
;; ============================================================

(defun my/drill-card-files ()
  "Return every Org note whose file name carries `my/drill-keyword'.
Returns nil when Denote is unavailable."
  (when (and (require 'denote nil t)
             (fboundp 'denote-directory-files)
             (fboundp 'denote-extract-keywords-from-path))
    (seq-filter (lambda (file)
                  (and (string-suffix-p ".org" file)
                       (member my/drill-keyword
                               (denote-extract-keywords-from-path file))))
                (denote-directory-files nil nil :text-only))))

;; ============================================================
;; RUNNING A SESSION
;; ============================================================

(defun my/drill--ensure-package ()
  "Load org-drill, or signal a `user-error' saying why it cannot be loaded.
The NOERROR argument of `require' covers a missing org-drill only; a
missing dependency of it (persist, compat) still signals, so the load is
wrapped as a whole."
  (condition-case err
      (require 'org-drill)
    (error
     (user-error "org-drill cannot be loaded (%s): M-x package-install RET org-drill"
                 (error-message-string err)))))

(defun my/drill--save-buffers (files)
  "Save the modified buffers visiting FILES and return how many were saved."
  (let ((count 0))
    (dolist (file files count)
      (let ((buffer (find-buffer-visiting file)))
        (when (and buffer (buffer-modified-p buffer))
          (with-current-buffer buffer
            (save-buffer))
          (setq count (1+ count)))))))

(defun my/drill--run (session files)
  "Call the function SESSION, then save whichever of FILES it modified.

Saving happens in `unwind-protect', so a session left with q or e, or
interrupted with C-g, still writes the scheduling data of the cards
already reviewed.  A deck buffer that was modified before the session
is saved as well; distinguishing the two edits is not possible from the
buffer state alone."
  (my/drill--ensure-package)
  (unwind-protect
      (funcall session)
    (let ((saved (my/drill--save-buffers files)))
      (when (> saved 0)
        (message "org-drill: saved %d file(s)" saved)))))

(defun my/drill--session-files ()
  "Return the decks plus the file of the current buffer, if any."
  (delete-dups
   (append (my/drill-card-files)
           (when buffer-file-name
             (list (expand-file-name buffer-file-name))))))

(defun my/drill--require-org-buffer ()
  "Signal a `user-error' unless the current buffer is in Org mode."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer")))

(defun my/drill-all ()
  "Review due cards from every deck (see `my/drill-card-files')."
  (interactive)
  (let ((files (my/drill-card-files)))
    (unless files
      (user-error "No Org note carries the keyword `%s'" my/drill-keyword))
    (my/drill--run (lambda () (org-drill files)) files)))

(defun my/drill-cram-all ()
  "Review every card from every deck, due or not.
Cram mode skips only cards reviewed within `org-drill-cram-hours'.  Meant
for the days right before an exam; it does not replace regular
sessions, and the ratings still reschedule the cards."
  (interactive)
  (let ((files (my/drill-card-files)))
    (unless files
      (user-error "No Org note carries the keyword `%s'" my/drill-keyword))
    (my/drill--run (lambda () (org-drill-cram files)) files)))

(defun my/drill-buffer ()
  "Review due cards in the current buffer, respecting any narrowing.
Narrowing first (C-x n s) limits the session to one subject."
  (interactive)
  (my/drill--require-org-buffer)
  (my/drill--run #'org-drill (my/drill--session-files)))

(defun my/drill-tree ()
  "Review due cards in the subtree at point."
  (interactive)
  (my/drill--require-org-buffer)
  (my/drill--run #'org-drill-tree (my/drill--session-files)))

(defun my/drill-resume ()
  "Resume the session last left with q or e."
  (interactive)
  (my/drill--run #'org-drill-resume (my/drill--session-files)))

;; ============================================================
;; WRITING CARDS
;; ============================================================

(defun my/drill--tag ()
  "Return the tag org-drill treats as a card marker."
  (if (boundp 'org-drill-question-tag) org-drill-question-tag "drill"))

(defun my/drill--card-heading-p ()
  "Return non-nil when the heading at point carries the card tag itself."
  (member (my/drill--tag) (org-get-tags nil t)))

(defun my/drill--insertion-point ()
  "Return (LEVEL . POSITION) at which a new card should be inserted.

Inside a card, including its answer: a sibling after that card.  Under
any other heading: a new last child of it.  Before the first heading: a
top-level heading at the end of the buffer."
  (save-excursion
    (if (org-before-first-heading-p)
        (cons 1 (point-max))
      (org-back-to-heading t)
      (let ((start (point)))
        (while (and (not (my/drill--card-heading-p))
                    (org-up-heading-safe)))
        (let ((level (if (my/drill--card-heading-p)
                         (org-current-level)
                       (goto-char start)
                       (1+ (org-current-level)))))
          (org-end-of-subtree t t)
          (cons level (point)))))))

(defun my/drill-insert-card (question)
  "Insert a card whose body is QUESTION and leave point in its answer.
Placement follows `my/drill--insertion-point'."
  (interactive (list (read-string "Question: ")))
  (my/drill--require-org-buffer)
  (when (string-empty-p (string-trim question))
    (user-error "Empty question"))
  (pcase-let* ((`(,level . ,position) (my/drill--insertion-point))
               (stars (make-string level ?*)))
    (goto-char position)
    (unless (bolp)
      (insert "\n"))
    (insert (format "%s %s :%s:\n%s\n\n%s* %s\n"
                    stars my/drill-card-title (my/drill--tag)
                    question stars my/drill-answer-heading))
    (save-excursion
      (forward-line -1)
      (org-back-to-heading t)
      (org-up-heading-safe)
      (org-align-tags))
    ;; Square brackets hide text as a cloze deletion during a session.
    ;; Usually intended, occasionally not, and invisible until the card
    ;; comes up -- so it is mentioned now.
    (when (string-match-p "\\[[^][]+\\]" question)
      (message "Note: text in [brackets] is hidden as a cloze during review"))))

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/drill-menu ()
  "Spaced repetition with org-drill."
  [["Review"
    ("r" "All decks"          my/drill-all)
    ("b" "This buffer"        my/drill-buffer)
    ("t" "Subtree at point"   my/drill-tree)
    ("R" "Resume last"        my/drill-resume)]
   ["Before an exam"
    ("c" "Cram all decks"     my/drill-cram-all)]
   ["Cards"
    ("n" "New card here"      my/drill-insert-card)]
   [("q" "Quit" transient-quit-one)]])

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    ;; Anchored on "x", which belongs to 12-transient itself, like the
    ;; writing-projects, tasks and habits entries.
    (my/transient-append 'my/notes-menu "x"
                         '("r" "Review cards (drill) →" my/drill-menu))))

(provide '43-drill)
;;; 43-drill.el ends here
