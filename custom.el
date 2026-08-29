;;; custom.el --- Customize-managed settings -*- lexical-binding: t; -*-

;; NOTE ON THE EMPTY `custom-set-faces' BLOCK
;; ------------------------------------------
;; This block used to pin about twenty Org faces to literal light
;; colours.  `custom-set-faces' writes the `user' theme, which outranks
;; every real theme by design, so those pins made a dark theme
;; impossible: modus-vivendi-tinted loaded and produced #fef8e0 blocks
;; on a dark background.
;;
;; Everything they expressed now lives in modules/09-theme.el:
;;   - colours          -> `modus-themes-common-palette-overrides'
;;   - heading sizes    -> `modus-themes-headings'
;;   - `:inherit fixed-pitch' on tables, blocks, code, verbatim,
;;     checkboxes and meta lines -> `modus-themes-mixed-fonts', which
;;     does exactly this and was already enabled, making those specs
;;     redundant even before the theme switch existed.
;;
;; Leave this block empty.  `M-x customize-face' writes here and its
;; result will beat 09-theme.el for that face, which is fine as a way
;; to try something out but is not where a setting should end up.  Move
;; anything worth keeping into 09-theme.el and delete it from here.

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(column-number-mode t)
 '(custom-safe-themes
   '("138ed99a323c1b93c52f4b3726caf2bc634b79a76fa63a3d3aff76394db5f28f"
     default))
 '(display-battery-mode t)
 '(display-line-numbers-type 'relative)
 '(display-time-mode t)
 '(package-selected-packages nil)
 '(recentf-filename-handlers '(abbreviate-file-name))
 '(safe-local-variable-values
   '((eval progn (visual-fill-column-mode -1)
           (setq-local visual-fill-column-width nil)
           (setq-local visual-fill-column-center-text nil))
     (org-confirm-babel-evaluate)))
 '(size-indication-mode t)
 '(tab-bar-mode t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
