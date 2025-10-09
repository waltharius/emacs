;;; 06-keybindings.el --- All keyboard shortcuts  -*- lexical-binding: t; -*-
;;; Commentary:
;; Description: Centralne miejsce na wszystkie skróty klawiszowe
;;              Updated: All C-c prefixes now use Transient menus
;;
;;; Code:

;; ============================================================
;; TRANSIENT MENUS - Main interface (replaces individual bindings)
;; ============================================================

;; Master help menu (guide + cheatsheet)
(global-set-key (kbd "C-c h") 'my/help-master-menu)
(global-set-key (kbd "C-c ?") 'my/help-master-menu)  ; Alternative

;; Core menus
(global-set-key (kbd "C-c n") 'my/notes-transient-menu)      ; Notes & Denote
(global-set-key (kbd "C-c p") 'my/project-transient-menu)    ; Projects
(global-set-key (kbd "C-c w") 'my/wellbeing-transient-menu)  ; Well-being
(global-set-key (kbd "C-c s") 'my/statistics-transient-menu) ; Statistics

;; Tool menus
(global-set-key (kbd "C-c F") 'my/spelling-transient-menu)      ; Flyspell
(global-set-key (kbd "C-c G") 'my/grammar-transient-menu)       ; LanguageTool
(global-set-key (kbd "C-c T") 'my/transclusion-transient-menu)  ; Org-transclusion
(global-set-key (kbd "C-c B") 'my/bookmarks-transient-menu)     ; Bookmarks

;; ============================================================
;; STANDALONE SHORTCUTS (not in menus)
;; ============================================================

;; Agenda (quick access, also available in C-c p menu)
(global-set-key (kbd "C-c a") 'org-agenda)

;; Spell checking - add word (used frequently in-flow)
(global-set-key (kbd "C-c i") 'my/spell-add-word-here)

;; Update modified timestamp
(global-set-key (kbd "C-c m") 'my/org-update-modified-property)

;; Dashboard quick access
(global-set-key (kbd "C-c d r") 'dashboard-refresh-buffer)
(global-set-key (kbd "C-c d d") 'my/open-dashboard)

;; ============================================================
;; ORG-MODE TIME TRACKING (standard bindings)
;; ============================================================

(global-set-key (kbd "C-c C-x C-i") 'org-clock-in)
(global-set-key (kbd "C-c C-x C-o") 'org-clock-out)
(global-set-key (kbd "C-c C-x C-x") 'org-clock-in-last)
(global-set-key (kbd "C-c C-x C-j") 'org-clock-goto)
(global-set-key (kbd "C-c C-x C-r") 'org-clock-report)

;; ============================================================
;; JOURNAL NAVIGATION (org-mode only)
;; ============================================================

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "M-p") 'my/journal-prev)
  (define-key org-mode-map (kbd "M-n") 'my/journal-next))

;; ============================================================
;; WHICH-KEY GROUP LABELS (organized C-c prefixes)
;; ============================================================

(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements
    ;; === Main menu groups ===
    "C-c h" "help-menu"
    "C-c ?" "help-menu"
    "C-c n" "notes-menu"
    "C-c p" "projects-menu"
    "C-c w" "wellbeing-menu"
    "C-c s" "statistics-menu"
    
    ;; === Tool menu groups ===
    "C-c f" "spelling-menu"
    "C-c g" "grammar-menu"
    "C-c t" "transclusion-menu"
    "C-c b" "bookmarks-menu"
    
    ;; === Standalone shortcuts ===
    "C-c a" "agenda"
    "C-c i" "add-to-dict"
    "C-c m" "update-modified"
    "C-c d" "dashboard"
    
    ;; === Dashboard subgroups ===
    "C-c d r" "refresh"
    "C-c d d" "open"))

(provide '06-keybindings)
;;; 06-keybindings.el ends here
