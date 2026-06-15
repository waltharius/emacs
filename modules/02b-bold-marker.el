;;; 02b-bold-marker.el --- Obsidian-style bold marker for org-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Replicates Obsidian's inline bold behavior in org-mode.
;;
;; PART 1 - Auto-bold on asterisk:
;;   Typing `word*` (asterisk directly after a word, no space) wraps the word
;;   in org-mode bold markers: *word*
;;   The trigger fires only when the char before `*` is a word character,
;;   preventing accidental activation on headlines, list items, etc.
;;
;; PART 2 - Expand bold backward:
;;   After the auto-bold fires, pressing C-= extends the bold region one word
;;   to the left.  Each subsequent press of C-= extends by one more word.
;;   The expansion state resets as soon as point moves away.
;;
;; Keybindings added here:
;;   C-= ... expand bold region backward, one word per press
;;
;; NOTE: Both functions are intentionally limited to org-mode buffers.
;;       Extending to markdown-mode would require different markers (**word**).
;;
;; NOTE: The keybinding is registered inside `with-eval-after-load' to avoid
;;       the "Symbol's value as variable is void: org-mode-map" error that
;;       occurs when this file is loaded before org.el is initialized.

;;; Code:

;; ============================================================
;; STATE: Track the opening marker position for expansion
;; ============================================================

(defvar my/bold-marker-start nil
  "Marker pointing to the opening `*` of the most recently inserted bold.
Used by `my/bold-expand-backward' to know where to move the opening marker.
Reset to nil whenever point moves away from inside the bold region.")

(defvar my/bold-marker-end nil
  "Marker pointing just after the closing `*` of the most recently inserted bold.
Used to detect whether point is still inside the bold region.")

;; ============================================================
;; PART 1: Auto-bold trigger on `*`
;; ============================================================

(defun my/bold-on-asterisk ()
  "Wrap the word before point in org bold markers when `*` is typed after it.

Fires via `post-self-insert-hook'.  Conditions that must ALL be true:
  - Current buffer is an org-mode buffer (or derived mode).
  - The character just inserted is `*'.
  - The character immediately before `*' is a word constituent (\\w).
  - There is no existing `*' immediately before that word char
    (prevents double-wrapping when user types a second asterisk).

When all conditions are met:
  1. Deletes the typed `*'.
  2. Moves backward to the start of the word.
  3. Inserts opening `*'.
  4. Moves forward to the end of the word.
  5. Inserts closing `*'.
  6. Records marker positions for `my/bold-expand-backward'."
  (when (and (derived-mode-p 'org-mode)
             (eq (char-before) ?*)
             ;; char before the asterisk must be a word character
             (save-excursion
               (backward-char 1)
               (looking-back "\\w" 1))
             ;; prevent double-trigger: char two positions back must NOT be `*'
             (not (save-excursion
                    (backward-char 2)
                    (eq (char-after) ?*))))
    (let (open-pos close-pos)
      ;; Remove the asterisk the user just typed
      (delete-char -1)
      ;; Remember end-of-word position
      (setq close-pos (point))
      ;; Move to start of word
      (save-excursion
        (backward-word 1)
        (setq open-pos (point))
        ;; Insert opening marker
        (goto-char open-pos)
        (insert "*"))
      ;; After inserting opening `*', close-pos shifted by 1
      (goto-char (+ close-pos 1))
      ;; Insert closing marker
      (insert "*")
      ;; Store marker positions for expansion (point is now after closing `*')
      (setq my/bold-marker-start (copy-marker (+ open-pos 0)))
      (setq my/bold-marker-end   (copy-marker (point))))))

(add-hook 'post-self-insert-hook #'my/bold-on-asterisk)

;; ============================================================
;; PART 2: Expand bold region backward (C-=, repeatable)
;; ============================================================

(defun my/bold-expand-backward ()
  "Extend the most recently created org bold region one word to the left.

Each call moves the opening `*' one word backward, effectively growing the
bold span.  Can be called repeatedly (e.g. C-= C-= C-=) to include more
words.

Preconditions:
  - `my/bold-marker-start' and `my/bold-marker-end' must be set (i.e., an
    auto-bold was just inserted and point has not moved away).
  - Point must still be at `my/bold-marker-end' (inside/adjacent to bold).

If the markers are stale or point has moved, the function does nothing and
emits a message explaining why."
  (interactive)
  (cond
   ;; Guard: markers not set yet
   ((or (null my/bold-marker-start)
        (null my/bold-marker-end)
        (not (marker-buffer my/bold-marker-start)))
    (message "No active bold region to expand. Type word* first."))

   ;; Guard: point moved away from the bold region
   ((not (= (point) (marker-position my/bold-marker-end)))
    (message "Point moved away from bold region; expansion cancelled.")
    (setq my/bold-marker-start nil
          my/bold-marker-end   nil))

   ;; Main expansion logic
   (t
    (save-excursion
      (goto-char (marker-position my/bold-marker-start))
      ;; Sanity check: there should be a `*' here
      (unless (eq (char-after) ?*)
        (user-error "Expected `*' at bold-marker-start position; aborting expansion"))
      ;; Delete the current opening marker
      (delete-char 1)
      ;; Move one word to the left (skip whitespace then jump over word)
      (skip-chars-backward " \t")
      (backward-word 1)
      ;; Insert new opening marker here
      (insert "*")
      ;; Update the start marker (now points to the newly inserted `*')
      (setq my/bold-marker-start (copy-marker (1- (point))))))))

;; ============================================================
;; KEYBINDING: C-= to expand bold backward
;; ============================================================
;; Wrapped in with-eval-after-load so that org-mode-map is guaranteed
;; to exist when this define-key call executes.  Without this guard,
;; loading the file before org.el causes:
;;   "Symbol's value as variable is void: org-mode-map"

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-=") #'my/bold-expand-backward))

;; ============================================================
;; RESET: Clear expansion state when point moves
;; ============================================================

(defun my/bold-reset-state ()
  "Reset bold-expansion state if point has moved away from the bold region.
Attached to `post-command-hook' so it fires after every command."
  (when (and my/bold-marker-end
             (marker-buffer my/bold-marker-end)
             (not (= (point) (marker-position my/bold-marker-end))))
    (setq my/bold-marker-start nil
          my/bold-marker-end   nil)))

(add-hook 'post-command-hook #'my/bold-reset-state)

(provide '02b-bold-marker)
;;; 02b-bold-marker.el ends here
