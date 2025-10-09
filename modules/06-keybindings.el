;;; 06-keybindings.el --- All keyboard shortcuts  -*- lexical-binding: t; -*-
;;; Commentary:
;; Description: Centralne miejsce na wszystkie skróty klawiszowe
;;              Updated: Denote shortcuts moved to Transient menu (C-c n)
;;
;;; Code:

;; ============================================================
;; SPELLING & GRAMMAR
;; ============================================================

;; --- Pisownia (Flyspell + Hunspell) ---
(global-set-key (kbd "C-c f n") 'flyspell-goto-next-error)
(global-set-key (kbd "C-c f p") 'my/flyspell-goto-previous-error)
(global-set-key (kbd "C-c f c") 'flyspell-correct-wrapper)
(global-set-key (kbd "C-c i") 'my/spell-add-word-here)

;; --- Gramatyka (LanguageTool) ---
(global-set-key (kbd "C-c g c") 'langtool-check)
(global-set-key (kbd "C-c g d") 'langtool-check-done)
(global-set-key (kbd "C-c g s") 'langtool-show-message-at-point)
(global-set-key (kbd "C-c g n") 'langtool-goto-next-error)
(global-set-key (kbd "C-c g p") 'langtool-goto-previous-error)
(global-set-key (kbd "C-c g f") 'langtool-correct-buffer)

;; ============================================================
;; DENOTE NOTES - Transient Menu (replaces individual C-c n X)
;; ============================================================

;; Main notes menu (all note functions in one place)
(global-set-key (kbd "C-c n") 'my/notes-transient-menu)

;; ============================================================
;; ORG-TRANSCLUSION: Embed notes
;; ============================================================

(global-set-key (kbd "C-c t a") 'org-transclusion-add)
(global-set-key (kbd "C-c t A") 'org-transclusion-add-all)
(global-set-key (kbd "C-c t t") 'org-transclusion-mode)
(global-set-key (kbd "C-c t m") 'org-transclusion-make-from-link)
(global-set-key (kbd "C-c t r") 'org-transclusion-remove)
(global-set-key (kbd "C-c t R") 'org-transclusion-remove-all)

;; ============================================================
;; STATISTICS & DASHBOARDS
;; ============================================================

(global-set-key (kbd "C-c s S") 'my/denote-count-words-all)
(global-set-key (kbd "C-c s s") 'my/denote-count-words-today)
(global-set-key (kbd "C-c s G") 'my/denote-writing-goal)
(global-set-key (kbd "C-c s d") 'my/denote-dashboard)
(global-set-key (kbd "C-c s p") 'my/denote-project-stats)
(global-set-key (kbd "C-c s P") 'my/denote-project-goal)
(global-set-key (kbd "C-c s m") 'my/denote-projects-menu)
(global-set-key (kbd "C-c s c") 'my/denote-cockpit)

;; ============================================================
;; WELL-BEING TRACKING
;; ============================================================

(global-set-key (kbd "C-c w w") 'my/denote-set-wellbeing)
(global-set-key (kbd "C-c w h") 'my/denote-wellbeing-history)
(global-set-key (kbd "C-c w g") 'my/denote-wellbeing-graph)
(global-set-key (kbd "C-c w p") 'my/denote-wellbeing-plot)
(global-set-key (kbd "C-c w f") 'my/denote-wellbeing-fill-missing)

;; ============================================================
;; DASHBOARD & UI
;; ============================================================

(global-set-key (kbd "C-c d r") 'dashboard-refresh-buffer)
(global-set-key (kbd "C-c d d") 'my/open-dashboard)

;; ============================================================
;; BOOKMARKS
;; ============================================================

(global-set-key (kbd "C-c b m") 'bookmark-set)
(global-set-key (kbd "C-c b j") 'bookmark-jump)
(global-set-key (kbd "C-c b l") 'bookmark-bmenu-list)

;; ============================================================
;; PROJECT MANAGEMENT - Transient Menu
;; ============================================================

;; Main project menu (all project functions)
(global-set-key (kbd "C-c p") 'my/project-transient-menu)

;; Org-agenda (standalone shortcut)
(global-set-key (kbd "C-c a") 'org-agenda)

;; Time tracking (standard Org-mode bindings)
(global-set-key (kbd "C-c C-x C-i") 'org-clock-in)
(global-set-key (kbd "C-c C-x C-o") 'org-clock-out)
(global-set-key (kbd "C-c C-x C-x") 'org-clock-in-last)
(global-set-key (kbd "C-c C-x C-j") 'org-clock-goto)
(global-set-key (kbd "C-c C-x C-r") 'org-clock-report)

;; Update modified timestamp
(global-set-key (kbd "C-c m") 'my/org-update-modified-property)

;; ============================================================
;; JOURNAL (org-journal integration)
;; ============================================================

;; Journal navigation (only in org-mode)
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "M-p") 'my/journal-prev)
  (define-key org-mode-map (kbd "M-n") 'my/journal-next))

;; ============================================================
;; WHICH-KEY GROUP LABELS (organized C-c menu)
;; ============================================================

(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements
    ;; === Main prefix groups ===
    "C-c n" "notes-menu"
    "C-c p" "projects-menu"
    "C-c f" "flyspell"
    "C-c g" "grammar"
    "C-c b" "bookmarks"
    "C-c s" "statistics"
    "C-c t" "transclusion"
    "C-c w" "wellbeing"
    "C-c d" "dashboard"
    "C-c a" "agenda"
    
    ;; === Flyspell subgroups ===
    "C-c f n" "next-error"
    "C-c f p" "prev-error"
    "C-c f c" "correct"
    
    ;; === Grammar (LanguageTool) subgroups ===
    "C-c g c" "check"
    "C-c g d" "done"
    "C-c g s" "show-error"
    "C-c g n" "next-error"
    "C-c g p" "prev-error"
    "C-c g f" "fix-buffer"
    
    ;; === Statistics subgroups ===
    "C-c s s" "stats-today"
    "C-c s S" "stats-all"
    "C-c s d" "dashboard"
    "C-c s p" "project-stats"
    
    ;; === Well-being subgroups ===
    "C-c w w" "set-wellbeing"
    "C-c w h" "history"
    "C-c w g" "graph"
    
    ;; === Bookmarks subgroups ===
    "C-c b m" "set"
    "C-c b j" "jump"
    "C-c b l" "list"
    
    ;; === Transclusion subgroups ===
    "C-c t a" "add"
    "C-c t t" "toggle-mode"
    "C-c t r" "remove"))

(provide '06-keybindings)
;;; 06-keybindings.el ends here
