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
          (let ((width (if is-docu my/fill-column-docu my-fill-column)))
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

(provide '10-visual-fill)
;;; 10-visual-fill.el ends here
