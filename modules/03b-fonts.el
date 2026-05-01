;;; 03b-fonts.el --- Font configuration with mixed fonts -*- lexical-binding: t; -*-
;;; Commentary:
;; Font configuration:
;; - Default: JetBrains Mono (monospace) for all files
;; - Journal notes: Playpen Sans Hebrew (handwriting style)
;; - Other org files: Keep monospace (explicitly disable variable-pitch)

;;; Code:

;; ============================================================
;; BASE FONTS - Monospace for everything by default
;; ============================================================

(set-face-attribute 'default nil
                    :font "JetBrains Mono-12"
                    :weight 'normal)

(set-face-attribute 'fixed-pitch nil
                    :font "JetBrains Mono-12")

;; Variable pitch font (used only in journal notes)
(set-face-attribute 'variable-pitch nil
                    :font "Playpen Sans Hebrew"
                    :weight 'normal)

;; ============================================================
;; JOURNAL-SPECIFIC FONT SETUP
;; ============================================================

(defun my/journal-font-setup ()
  "Enable handwriting font ONLY for journal notes.
   Other org files EXPLICITLY stay monospace."
  (if (and (buffer-file-name)
           (string-match-p "journal" (buffer-file-name)))
      ;; This IS a journal file - enable handwriting font
      (progn
        (variable-pitch-mode 1)
        (visual-line-mode 1)
        (face-remap-add-relative 'variable-pitch
                                 :family "Playpen Sans Hebrew"
                                 :height 1.0))
    ;; This is NOT a journal file - ensure monospace
    (progn
      (variable-pitch-mode -1)     ; Disable variable-pitch
      (visual-line-mode 1))))

(add-hook 'org-mode-hook 'my/journal-font-setup)

;; ============================================================
;; KEEP MONOSPACE FOR CODE, TABLES, BLOCKS (in journal too)
;; ============================================================

(with-eval-after-load 'org
  (set-face-attribute 'org-table nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-code nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-block nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-verbatim nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-special-keyword nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-meta-line nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-checkbox nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-link nil :inherit 'fixed-pitch))

;; ============================================================
;; FLEETING NOTES - Beautiful quote styling with serif font
;; ============================================================

(with-eval-after-load 'org
  ;; Quotes get serif font (like in books!)
  (set-face-attribute 'org-quote nil
                      :family "Georgia"         ; Serif font for quotes
                      :slant 'italic
                      :height 1.1               ; Slightly bigger
                      :foreground nil)
  
  ;; BEGIN/END stay small and monospace
  (set-face-attribute 'org-block-begin-line nil
                      :inherit 'fixed-pitch
                      :foreground "#888888"
                      :height 0.85)
  
  (set-face-attribute 'org-block-end-line nil
                      :inherit 'fixed-pitch
                      :foreground "#888888"
                      :height 0.85))

(provide '03b-fonts)
;;; 03b-fonts.el ends here
