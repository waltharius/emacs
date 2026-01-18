;;; 03b-fonts.el --- Font configuration with mixed fonts -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:
;; Czcionki podstawowe
(set-face-attribute 'default nil
                    :font "JetBrains Mono-12"
                    :weight 'normal)

(set-face-attribute 'fixed-pitch nil
                    :font "JetBrains Mono-12")

;; CZCIONKA DO JOURNALA - pismo odręczne
;; Opcje: "Snell Roundhand", "Bradley Hand", "Noteworthy"
;; lub zainstaluj: Dancing Script, Cedarville Cursive
(set-face-attribute 'variable-pitch nil
                    :font "Playpen Sans Hebrew"
                    :weight 'normal)

;; Włącz mixed fonts w org-mode
(add-hook 'org-mode-hook 'variable-pitch-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

;; Zachowaj monospace dla kodu, tabel, bloków
(with-eval-after-load 'org
  (set-face-attribute 'org-table nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-code nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-block nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-verbatim nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-special-keyword nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-meta-line nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-checkbox nil :inherit 'fixed-pitch))

;; Specjalna czcionka TYLKO dla journali
(defun my/journal-font-setup ()
  "Większa, ładniejsza czcionka dla journali."
  (when (and (buffer-file-name)
             (string-match-p "journal" (buffer-file-name)))
    (face-remap-add-relative 'variable-pitch
                             :family "Playpen Sans Hebrew"
                             :height 1.0)))

(add-hook 'org-mode-hook 'my/journal-font-setup)

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
