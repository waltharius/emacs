;;; 02b-bold-marker.el --- Obsidian-style inline markers for org-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Replicates Obsidian's inline formatting behavior for org-mode.
;;
;; PART 1 - Auto-wrap on trigger character:
;;   Typing a trigger character directly after a word (no space) wraps that
;;   word in the corresponding org-mode inline markers:
;;
;;     word*   ->  *word*    bold
;;     word~   ->  ~word~    code
;;     word=   ->  =word=    verbatim
;;
;;   A quoted phrase is wrapped whole.  Typing the trigger right after a
;;   closing quote walks back to the quote that opened the phrase and
;;   puts the marker in front of it:
;;
;;     "a quoted phrase"*   ->   *"a quoted phrase"*
;;
;;   The markers land OUTSIDE the quotes, so one keystroke after the
;;   closing quote emphasises the phrase together with its punctuation.
;;   Org renders that: the default `org-emphasis-regexp-components'
;;   forbids only whitespace at the border of an emphasised span, and a
;;   quote is not whitespace.
;;
;;   `/' and `_' were triggers too and were removed 2026-08.  Both occur
;;   far more often as ordinary punctuation than as emphasis: `/' in
;;   paths, URLs, dates and alternatives written as this/that, `_' in
;;   file names, identifiers and code.  A trigger that fires when it was
;;   not wanted costs an undo and breaks the sentence being written,
;;   which is a worse trade than typing /italic/ by hand.  `*', `~' and
;;   `=' do not appear inside words in prose, so they stay.
;;
;;   The trigger fires only when:
;;     - The buffer is in org-mode (or a derived mode).
;;     - The character immediately before the trigger is a word constituent.
;;     - The same trigger character does not already appear immediately before
;;       that word character (prevents double-wrapping).
;;
;; PART 2 - Expand marked region backward (C-=):
;;   After auto-wrap fires, pressing C-= moves the opening marker one word
;;   to the left, extending the marked span.  Each subsequent C-= extends
;;   by one more word.  State resets when point moves away.
;;
;; Keybindings:
;;   C-=   expand inline marker region one word backward (repeatable)
;;
;; NOTE: Trigger chars that appear mid-word in URLs, paths, or dates are NOT
;;       wrapped because org requires a word boundary before the trigger.
;;       Use \char to insert a literal trigger character without formatting.
;;
;; NOTE: The org-mode-map keybinding is registered inside with-eval-after-load
;;       to avoid "Symbol's value as variable is void: org-mode-map" on startup.

;;; Code:

;; ============================================================
;; CONFIGURATION: trigger chars -> (open-marker close-marker)
;; ============================================================

(defvar my/inline-marker-triggers
  '((?*  "*"  "*")   ; bold
    (?~  "~"  "~")   ; code
    (?=  "="  "="))  ; verbatim
  "Alist of (trigger-char open-marker close-marker) for org inline formatting.
Each entry causes `my/inline-marker-on-trigger' to wrap the preceding word
when trigger-char is typed directly after it.

Only characters that do not occur inside words in ordinary prose belong
here.  `/' and `_' were removed: they appear constantly in paths, URLs,
dates, this/that alternatives, file names and code, and a trigger that
fires unasked costs an undo and interrupts the sentence.  Italic and
underline are typed by hand, which is rarer than all of those.")

;; ============================================================
;; STATE: track opening marker position for C-= expansion
;; ============================================================

(defvar my/inline-marker-wrap-quotes t
  "When non-nil, a trigger typed after a closing quote wraps the phrase.
See the header of this file.  Only the ASCII double quote is handled:
that is what `electric-pair-mode' inserts in these buffers, and the
typographic pairs are not typed here.")

(defvar my/inline-marker-quote-stop-at-paragraph t
  "When non-nil, the search for the opening quote stops at the paragraph.

The phrase may run over as many hard-broken lines as it likes -- docu
notes are written that way and the search is meant to cross them -- but
not past a blank line.  A quote that appears to open in an earlier
paragraph is, in practice, a stray quote somewhere above, and wrapping
everything between it and the cursor in bold is a worse outcome than
leaving the typed character where it is.

Set to nil to search back to the beginning of the buffer instead.")

(defvar my/inline-marker-start nil
  "Buffer marker at the opening marker character of the last auto-wrap.
Used by `my/inline-marker-expand-backward' to move the opening marker left.
Set to nil when point moves away from the end of the wrapped region.")

(defvar my/inline-marker-end nil
  "Buffer marker just after the closing marker of the last auto-wrap.
Used to detect whether point is still adjacent to the wrapped region.")

(defvar my/inline-marker-open-char nil
  "The opening marker string of the last auto-wrap (e.g. \"*\", \"/\", \"~\").
Used by `my/inline-marker-expand-backward' to verify marker integrity.")

;; ============================================================
;; PART 1: generic auto-wrap on trigger character
;; ============================================================

(defun my/inline-marker--wrap (open-pos close-pos open close)
  "Put OPEN before OPEN-POS and CLOSE after CLOSE-POS, and record the span.

CLOSE-POS is where the closing marker goes, which is where the trigger
character was before it was deleted.  The opening marker is inserted
first, so CLOSE-POS has to be shifted by its length afterwards -- the
one piece of arithmetic in this file worth reading twice."
  (save-excursion
    (goto-char open-pos)
    (insert open))
  (goto-char (+ close-pos (length open)))
  (insert close)
  (setq my/inline-marker-start     (copy-marker open-pos)
        my/inline-marker-end       (copy-marker (point))
        my/inline-marker-open-char open))

(defun my/inline-marker--quote-opening (closing)
  "Return the position of the quote opening the phrase closed at CLOSING.

CLOSING is the buffer position OF the closing quote character.  Nil
when no opening quote is found within the limit set by
`my/inline-marker-quote-stop-at-paragraph\='.

Nothing is inserted when this returns nil, and the typed trigger is
left alone, so the buffer shows `\"*\' -- which says, on the screen,
that the opening quote is missing or further away than the search
reached.  That is information; silently wrapping the last word instead
would not be."
  (save-excursion
    (goto-char closing)
    (let ((limit (if my/inline-marker-quote-stop-at-paragraph
                     (save-excursion (backward-paragraph) (point))
                   (point-min))))
      (when (search-backward "\"" limit t)
        (point)))))

(defun my/inline-marker-on-trigger ()
  "Wrap the word or quoted phrase before point when a trigger char is typed.

Fires via `post-self-insert-hook\='.  Looks up the just-inserted
character in `my/inline-marker-triggers\=' and, when it is one, decides
what to wrap from the character in front of it:

  a word constituent   the preceding word
  a closing quote      the whole quoted phrase, quotes included

Neither fires when the same trigger character already sits in front of
what would be wrapped, which is what stops a second press from wrapping
an already-wrapped span.

Side effects: sets `my/inline-marker-start\=', `my/inline-marker-end\='
and `my/inline-marker-open-char\=' for
`my/inline-marker-expand-backward\='."
  (when (derived-mode-p 'org-mode)
    (let* ((trigger (char-before))
           (entry   (assq trigger my/inline-marker-triggers))
           ;; Position OF the trigger character, not after it.
           (trigger-pos (and entry (1- (point))))
           (before (and entry (char-before trigger-pos))))
      (when entry
        (let ((open (nth 1 entry))
              (close (nth 2 entry)))
          (cond
           ;; --- a quoted phrase -------------------------------------
           ((and my/inline-marker-wrap-quotes
                 (eq before ?\")
                 (> trigger-pos (point-min)))
            (when-let* ((quote-open (my/inline-marker--quote-opening
                                     (1- trigger-pos))))
              ;; Already wrapped: the same marker sits before the
              ;; opening quote.
              (unless (eq (char-before quote-open) trigger)
                (delete-char -1)
                (my/inline-marker--wrap quote-open (point) open close))))
           ;; --- a bare word -----------------------------------------
           ((and before
                 (eq ?w (char-syntax before))
                 ;; The same trigger must not already precede the word.
                 (not (save-excursion
                        (backward-char 2)
                        (eq (char-after) trigger))))
            (delete-char -1)
            (let ((close-pos (point))
                  (open-pos (save-excursion (backward-word 1) (point))))
              (my/inline-marker--wrap open-pos close-pos open close)))))))))

(add-hook 'post-self-insert-hook #'my/inline-marker-on-trigger)

;; ============================================================
;; PART 2: expand marked region backward (C-=, repeatable)
;; ============================================================

(defun my/inline-marker-expand-backward ()
  "Extend the most recently auto-wrapped org inline region one word to the left.

Moves the opening marker one word backward each time it is called.
Can be repeated (C-= C-= C-=) to grow the region further.

Aborts with a message if:
  - No auto-wrap has been performed yet (markers are nil).
  - Point has moved away from the end of the wrapped region.
  - The expected opening marker character is not found at the recorded position."
  (interactive)
  (cond
   ;; Guard: no active region
   ((or (null my/inline-marker-start)
        (null my/inline-marker-end)
        (not (marker-buffer my/inline-marker-start)))
    (message "No active inline region to expand. Type word<trigger> first."))

   ;; Guard: point has moved away
   ((not (= (point) (marker-position my/inline-marker-end)))
    (message "Point moved away from inline region; expansion cancelled.")
    (setq my/inline-marker-start     nil
          my/inline-marker-end       nil
          my/inline-marker-open-char nil))

   ;; Main expansion
   (t
    (save-excursion
      (goto-char (marker-position my/inline-marker-start))
      ;; Verify the opening marker is where we expect it
      (unless (and my/inline-marker-open-char
                   (looking-at (regexp-quote my/inline-marker-open-char)))
        (user-error "Expected '%s' at marker-start position; aborting expansion"
                    my/inline-marker-open-char))
      ;; Delete current opening marker
      (delete-char (length my/inline-marker-open-char))
      ;; Skip any whitespace to the left, then move one full word left
      (skip-chars-backward " \t")
      (backward-word 1)
      ;; Insert new opening marker here
      (insert my/inline-marker-open-char)
      ;; Update start marker (points to the newly inserted marker)
      (setq my/inline-marker-start
            (copy-marker (- (point) (length my/inline-marker-open-char))))))))

;; ============================================================
;; KEYBINDING: C-= expands inline region backward
;; ============================================================
;; Scoped to org-mode-map so it does not override global C-= elsewhere.
;; Wrapped in with-eval-after-load to guarantee org-mode-map exists.

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-=") #'my/inline-marker-expand-backward))

;; ============================================================
;; RESET: clear expansion state when point moves away
;; ============================================================

(defun my/inline-marker-reset-state ()
  "Clear inline-marker expansion state when point leaves the wrapped region.
Attached to `post-command-hook'; runs after every command."
  (when (and my/inline-marker-end
             (marker-buffer my/inline-marker-end)
             (not (= (point) (marker-position my/inline-marker-end))))
    (setq my/inline-marker-start     nil
          my/inline-marker-end       nil
          my/inline-marker-open-char nil)))

(add-hook 'post-command-hook #'my/inline-marker-reset-state)

(provide '02b-bold-marker)
;;; 02b-bold-marker.el ends here
