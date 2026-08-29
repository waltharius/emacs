;;; 10-visual-fill.el --- Visual fill column: single source of truth -*- lexical-binding: t; -*-
;;; Commentary:
;; ALL visual-fill-column and line-wrapping logic lives here.
;; No other module should set visual-fill-column-* variables.
;;
;; Rules:
;;   Files under ~/notes/         -> visual-fill ON, text centered
;;     :docu: tag in #+filetags:  -> width 100
;;     all other notes            -> width 80  (my-fill-column)
;;   Files outside ~/notes/       -> visual-fill OFF, full-width
;;     (intentional: clear visual signal that you left the notes tree)
;;   Non-org / non-text files     -> visual-fill never activated
;;
;; display-fill-column-indicator-mode is never enabled by this config
;; (clean margins, no boundary lines).

;;; Code:

;; ============================================================
;; PACKAGE: load visual-fill-column
;; ============================================================

(defcustom my/fill-column-docu 100
  "Text column width for notes tagged `:docu:'.
Separate from `my-fill-column' because docu notes hold command lines
and code that read badly when wrapped early.

The value is in CHARACTERS of the buffer's default face, not in
pixels, so a buffer using a proportional face renders the same number
narrower.  See the comment in `my/visual-fill-notes-setup'."
  :type 'integer :group 'convenience)

(use-package visual-fill-column
  :ensure t
  :config
  ;; Conservative global defaults — actual per-buffer values are set
  ;; by my/visual-fill-notes-setup below.  Nothing else should touch
  ;; these setq-defaults.
  (setq-default visual-fill-column-width       my-fill-column) ; 80
  (setq-default visual-fill-column-center-text nil)            ; no centering outside notes
  (setq-default visual-fill-column-extra-text-width '(0 . 0))
  (setq-default visual-fill-column-fringes-outside-margins nil))

;; ============================================================
;; CORE SETUP FUNCTION
;; ============================================================

(defun my/visual-fill-notes-setup ()
  "Configure visual-fill-column for the current buffer.

Called from find-file-hook and org-mode-hook.

Files under `my-notes-dir' (~/notes/):
  - Enable visual-fill-column-mode and visual-line-mode.
  - Center text.
  - Width = 100 when #+filetags contains :docu:, else `my-fill-column' (80).

Files outside `my-notes-dir':
  - Disable visual-fill-column-mode if active.
  - Full-width display (intentional visual signal)."
  (when (and (buffer-file-name)
             (derived-mode-p 'org-mode 'text-mode))
    (let ((in-notes (string-match-p
                     (regexp-quote (expand-file-name my-notes-dir))
                     (buffer-file-name))))
      (if (not in-notes)
          ;; Outside ~/notes/ -> full width, no centering
          (when (bound-and-true-p visual-fill-column-mode)
            (visual-fill-column-mode -1))
        ;; Inside ~/notes/ -> centered column
        ;;
        ;; WIDTH IS A CHARACTER COUNT, AND CHARACTERS DIFFER IN WIDTH
        ;; ---------------------------------------------------------
        ;; visual-fill-column turns `visual-fill-column-width' into
        ;; margins by multiplying it by the width of one character in
        ;; the buffer's default face.  A buffer running a proportional
        ;; face (any silo whose `:body' is `proportional' in
        ;; 03b-fonts.el) has a narrower average character than one
        ;; running JetBrains Mono, so the SAME number yields a NARROWER
        ;; column.  That is why a docu note at 100 and a pks note at 80
        ;; differ by much more than the 20 columns suggest.
        (let ((is-docu nil))
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^#\\+filetags:.*:docu:" nil t)
              (setq is-docu t)))
          ;; Precedence: the note's own `#+text_width:', then the
          ;; :docu: width, then the global default.  A note that states
          ;; a width carries that width everywhere -- to another
          ;; machine over Syncthing, into git, into any other editor
          ;; that reads the front matter.
          (let ((width (or (my/note-keyword-number "text_width")
                           (if is-docu my/fill-column-docu my-fill-column))))
            (setq fill-column                          width)
            (setq-local visual-fill-column-width       width)
            (setq-local visual-fill-column-center-text t))
          (visual-line-mode 1)
          (visual-fill-column-mode 1)
          ;; Never show the indicator line (clean margins).
          (display-fill-column-indicator-mode -1)
          (visual-fill-column--adjust-window))))))

;; ============================================================
;; HOOKS
;; ============================================================

;; find-file-hook : fires when a file is opened (covers all denote notes)
;; org-mode-hook  : fires when org-mode activates (covers *Capture* etc.)
;;                  the guard inside the function handles non-note files.
(add-hook 'find-file-hook #'my/visual-fill-notes-setup)
(add-hook 'org-mode-hook  #'my/visual-fill-notes-setup)

;; ============================================================
;; TOGGLE FUNCTIONS (used by transient menu 12-transient.el)
;; ============================================================

(defun my/toggle-visual-fill-column ()
  "Toggle visual-fill-column-mode in current buffer."
  (interactive)
  (if (bound-and-true-p visual-fill-column-mode)
      (progn
        (visual-fill-column-mode -1)
        (message "Centered layout: OFF"))
    (progn
      (visual-fill-column-mode 1)
      (message "Centered layout: ON"))))

(defun my/toggle-visual-fill-column-center ()
  "Toggle text centering in current buffer (transient menu: C-c n y)."
  (interactive)
  (if (bound-and-true-p visual-fill-column-mode)
      (progn
        (setq-local visual-fill-column-center-text
                    (not visual-fill-column-center-text))
        (visual-fill-column--adjust-window)
        (message "Centering: %s"
                 (if visual-fill-column-center-text "✅ ON" "❌ OFF")))
    (message "⚠️ visual-fill-column-mode not active in this buffer")))

;; ============================================================
;; GLOBALLY DISABLE FILL-COLUMN-INDICATOR
;; ============================================================
;; Belt-and-suspenders: turn off any indicator lines that may have been
;; activated before this module loaded.
(when (fboundp 'global-display-fill-column-indicator-mode)
  (global-display-fill-column-indicator-mode -1))

;; ============================================================
;; CHANGING THE WIDTH, INTERACTIVELY
;; ============================================================
;; `C-c u w' enters a repeat map: `+' and `-' widen and narrow the
;; current buffer live, `0' returns it to what the rules above would
;; give it, `d' adopts the current width as the global default, and `s'
;; writes it into this note's front matter.  Any other key leaves.
;;
;; Buffer-local while adjusting, so a width can be tried without
;; committing to it.  Nothing is written anywhere until `d' or `s'.
;;
;; A REMINDER ABOUT THE UNIT.  The number is CHARACTERS of the buffer's
;; default face, and visual-fill-column turns it into margins by
;; multiplying by the width of one character.  A pks note in a
;; proportional face and a docu note in JetBrains Mono therefore look
;; different at the same number.  Adjust each kind separately and
;; expect the figures to differ; that is the unit doing its job, not a
;; bug.



(defun my/text-width--apply (width &optional message-suffix)
  "Set this buffer's text column to WIDTH and keep the repeat map alive."
  (setq-local visual-fill-column-width (max 30 (min 300 width)))
  (setq fill-column visual-fill-column-width)
  (when (bound-and-true-p visual-fill-column-mode)
    (visual-fill-column--adjust-window))
  (force-window-update (selected-window))
  (message "Width %d   [+ - 0]  d=make default  s=save in note%s"
           visual-fill-column-width (or message-suffix ""))
  (set-transient-map my/text-width-repeat-map t))

(defun my/text-width-increase ()
  "Widen the current buffer's text column by five characters."
  (interactive)
  (my/text-width--apply (+ visual-fill-column-width 5)))

(defun my/text-width-decrease ()
  "Narrow the current buffer's text column by five characters."
  (interactive)
  (my/text-width--apply (- visual-fill-column-width 5)))

(defun my/text-width-reset ()
  "Return this buffer to the width the normal rules would give it."
  (interactive)
  (kill-local-variable 'visual-fill-column-width)
  (my/visual-fill-notes-setup)
  (my/text-width--apply visual-fill-column-width))

(defun my/text-width-save-as-default ()
  "Adopt the current width as the default for all notes.
Writes `my-fill-column' to `my/ui-state-file', so the choice survives
a restart without editing 00-core.el.  Notes tagged `:docu:' and notes
carrying their own `#+text_width:' are unaffected."
  (interactive)
  (setq my-fill-column visual-fill-column-width)
  (my/ui-state-set :fill-column my-fill-column)
  (my/text-width--apply visual-fill-column-width "  -- saved as default"))

(defun my/text-width-save-to-note ()
  "Write the current width into this note's front matter."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (my/note-keyword-set "text_width" visual-fill-column-width)
  (my/text-width--apply visual-fill-column-width
                        "  -- written to front matter, buffer not saved"))

(defvar my/text-width-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "+") #'my/text-width-increase)
    (define-key map (kbd "=") #'my/text-width-increase)
    (define-key map (kbd "-") #'my/text-width-decrease)
    (define-key map (kbd "0") #'my/text-width-reset)
    (define-key map (kbd "d") #'my/text-width-save-as-default)
    (define-key map (kbd "s") #'my/text-width-save-to-note)
    map)
  "Transient map active while adjusting the text width.")

(defun my/text-width-adjust ()
  "Adjust the text width, then keep adjusting with + and -."
  (interactive)
  (my/text-width--apply (or visual-fill-column-width my-fill-column)))

(global-set-key (kbd "C-c u w") #'my/text-width-adjust)

;; Adopt a previously saved default.  Late in the file so that the
;; `setq-default' in the `use-package' form above has already run.
(when-let* ((width (my/ui-state-get :fill-column)))
  (setq my-fill-column width)
  (setq-default visual-fill-column-width width))

(provide '10-visual-fill)
;;; 10-visual-fill.el ends here
