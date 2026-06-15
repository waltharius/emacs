;;; 02b-bold-marker.el --- Obsidian-style inline markers for org-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Replicates Obsidian's inline formatting behavior for org-mode.
;;
;; PART 1 - Auto-wrap on trigger character:
;;   Typing a trigger character directly after a word (no space) wraps that
;;   word in the corresponding org-mode inline markers:
;;
;;     word*   ->  *word*    bold
;;     word_   ->  _word_    underline
;;     word/   ->  /word/    italic
;;     word~   ->  ~word~    code
;;     word=   ->  =word=    verbatim
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
    (?_  "_"  "_")   ; underline
    (?/  "/"  "/")   ; italic
    (?~  "~"  "~")   ; code
    (?=  "="  "="))  ; verbatim
  "Alist of (trigger-char open-marker close-marker) for org inline formatting.
Each entry causes `my/inline-marker-on-trigger' to wrap the preceding word
when trigger-char is typed directly after it.")

;; ============================================================
;; STATE: track opening marker position for C-= expansion
;; ============================================================

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

(defun my/inline-marker-on-trigger ()
  "Wrap the word before point in org inline markers when a trigger char is typed.

Fires via `post-self-insert-hook'.  Looks up the just-inserted character in
`my/inline-marker-triggers'.  If found, and if the character immediately
before the trigger is a word constituent (not the same trigger char), wraps
the preceding word with the configured open/close marker pair.

Side effects:
  - Sets `my/inline-marker-start', `my/inline-marker-end', and
    `my/inline-marker-open-char' for use by `my/inline-marker-expand-backward'."
  (when (derived-mode-p 'org-mode)
    (let* ((trigger (char-before))
           (entry   (assq trigger my/inline-marker-triggers)))
      (when (and entry
                 ;; char before the trigger must be a word character
                 (save-excursion
                   (backward-char 1)
                   (looking-back "\\w" 1))
                 ;; same trigger char must NOT immediately precede the word char
                 ;; (prevents double-wrapping if user types the char twice)
                 (not (save-excursion
                        (backward-char 2)
                        (eq (char-after) trigger))))
        (let ((open  (nth 1 entry))
              (close (nth 2 entry))
              open-pos close-pos)
          ;; Remove the trigger character the user just typed
          (delete-char -1)
          ;; Remember end-of-word position
          (setq close-pos (point))
          ;; Insert opening marker at start of word
          (save-excursion
            (backward-word 1)
            (setq open-pos (point))
            (insert open))
          ;; close-pos shifted right by length of open marker
          (goto-char (+ close-pos (length open)))
          ;; Insert closing marker
          (insert close)
          ;; Record state for expansion
          (setq my/inline-marker-start    (copy-marker open-pos)
                my/inline-marker-end      (copy-marker (point))
                my/inline-marker-open-char open))))))

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
