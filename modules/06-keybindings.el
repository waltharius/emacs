;;; 06-keybindings.el --- All keyboard shortcuts  -*- lexical-binding: t; -*-
;;
;; Description: Centralne miejsce na wszystkie skróty klawiszowe
;;
;;; Code:

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

;; --- UI ---
(global-set-key (kbd "C-c n e") 'open-init-el-bottom-split)

;; --- Denote: tworzenie notatek ---
(global-set-key (kbd "C-c n n") 'denote)
(global-set-key (kbd "C-c n j") 'my/denote-journal)
(global-set-key (kbd "C-c n J") 'my/denote-journal-date)
(global-set-key (kbd "C-c n z") 'my/denote-zettel)
(global-set-key (kbd "C-c n o") 'my/denote-osoba)
(global-set-key (kbd "C-c n s") 'my/denote-skroty)
(global-set-key (kbd "C-c n b") 'my/denote-base)
(global-set-key (kbd "C-c n h") 'insert-current-time)

;; --- Denote: wyszukiwanie ---
(autoload 'denote-open-or-create "denote" nil t)
(autoload 'consult-denote-grep "consult-denote" nil t)
(autoload 'consult-denote-find "consult-denote" nil t)

(global-set-key (kbd "C-c n f") 'denote-open-or-create)
(global-set-key (kbd "C-c n g") 'consult-denote-grep)
(global-set-key (kbd "C-c n F") 'consult-denote-find)

;; --- Denote: linkowanie ---
(autoload 'denote-link "denote" nil t)
(autoload 'denote-backlinks "denote" nil t)
(autoload 'denote-add-links "denote" nil t)
(autoload 'denote-link-or-create "denote" nil t)
(autoload 'denote-link-after-creating "denote" nil t)

(global-set-key (kbd "C-c n i") 'denote-link)
(global-set-key (kbd "C-c n B") 'denote-backlinks)
(global-set-key (kbd "C-c n L") 'denote-add-links)
(global-set-key (kbd "C-c n I") 'denote-link-or-create)
(global-set-key (kbd "C-c n C") 'denote-link-after-creating)

;; --- Denote: zarządzanie ---
(autoload 'denote-keywords-add "denote" nil t)
(autoload 'denote-keywords-remove "denote" nil t)
(autoload 'denote-rename-file "denote" nil t)
(autoload 'denote-rename-file-using-front-matter "denote" nil t)

(global-set-key (kbd "C-c n t a") 'denote-keywords-add)
(global-set-key (kbd "C-c n t r") 'denote-keywords-remove)
(global-set-key (kbd "C-c n r") 'denote-rename-file)
(global-set-key (kbd "C-c n R") 'denote-rename-file-using-front-matter)

;; --- Org-transclusion: embed notes ---
(global-set-key (kbd "C-c t a") 'org-transclusion-add)
(global-set-key (kbd "C-c t A") 'org-transclusion-add-all)
(global-set-key (kbd "C-c t t") 'org-transclusion-mode)
(global-set-key (kbd "C-c t m") 'org-transclusion-make-from-link)
(global-set-key (kbd "C-c t r") 'org-transclusion-remove)
(global-set-key (kbd "C-c t R") 'org-transclusion-remove-all)

;; --- Zlicznie statystyk ze wszystkich notatek ---
(global-set-key (kbd "C-c s S") 'my/denote-count-words-all)
(global-set-key (kbd "C-c s s") 'my/denote-count-words-today)
(global-set-key (kbd "C-c s G") 'my/denote-writing-goal)
(global-set-key (kbd "C-c s d") 'my/denote-dashboard)
(global-set-key (kbd "C-c s p") 'my/denote-project-stats)
(global-set-key (kbd "C-c s P") 'my/denote-project-goal)
(global-set-key (kbd "C-c s m") 'my/denote-projects-menu)
(global-set-key (kbd "C-c s c") 'my/denote-cockpit)

;; --- Well-being w journalu ---
(global-set-key (kbd "C-c w w") 'my/denote-set-wellbeing)
(global-set-key (kbd "C-c w h") 'my/denote-wellbeing-history)
(global-set-key (kbd "C-c w g") 'my/denote-wellbeing-graph)
(global-set-key (kbd "C-c w p") 'my/denote-wellbeing-plot)
(global-set-key (kbd "C-c w f") 'my/denote-wellbeing-fill-missing)

;; --- Akademicki flow ---
(global-set-key (kbd "C-c n P") 'my/denote-philosopher)  ; Filozof
(global-set-key (kbd "C-c n L") 'my/denote-literature)   ; Lektura
(global-set-key (kbd "C-c n E") 'my/denote-essay)        ; Esej

;; --- Folgezettel (smart Zettelkasten) ---
(global-set-key (kbd "C-c n Z") 'my/denote-zettel-smart)     ; Smart Zettel
(global-set-key (kbd "C-c n T") 'my/denote-zettel-tree)      ; Tree view
(global-set-key (kbd "C-c n C") 'my/denote-find-children)    ; Find children

(provide '06-keybindings)
;;; 06-keybindings.el ends here
