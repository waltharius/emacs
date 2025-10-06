;;; 01-packages.el --- Package management and Dashboard -*- lexical-binding: t; -*-
;;
;; Description: Konfiguracja pakietów + Dashboard PKM
;;
;;; Code:

;; ============================================================
;; PACKAGE REPOSITORIES
;; ============================================================

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)

;; Install use-package if not present
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; Disable native compilation warnings
(setq native-comp-async-report-warnings-errors nil)

;; ============================================================
;; UTILITY PACKAGES
;; ============================================================

;; Which-key: Show keybinding hints
(use-package which-key
  :ensure t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.5))

;; Htmlize: Export to HTML with colors
(use-package htmlize
  :ensure t)

;; Org-transclusion: Embed notes
(use-package org-transclusion
  :ensure t
  :after org)

;; Gnuplot: Charts in Org-mode
(use-package gnuplot
  :ensure t)

;; Vertico: Better minibuffer
(use-package vertico
  :ensure t
  :init
  (vertico-mode))

;; Marginalia: Annotations in minibuffer
(use-package marginalia
  :ensure t
  :init
  (marginalia-mode))

;; Orderless: Flexible completion
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic)))

;; Org-roam-ui: Visual graph
(use-package org-roam-ui
  :ensure t
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t)
  (setq org-roam-ui-follow t)
  (setq org-roam-ui-update-on-save t))

;; ============================================================
;; DASHBOARD: PKM Statistics + Goals
;; ============================================================

;; ----- HELPER FUNCTIONS (before Dashboard) -----

(defvar my/daily-goals-file 
  (expand-file-name "daily-goals.el" user-emacs-directory)
  "File storing daily writing goals.")

(defun my/load-daily-goals ()
  "Load daily goals from file."
  (if (file-exists-p my/daily-goals-file)
      (with-temp-buffer
        (insert-file-contents my/daily-goals-file)
        (goto-char (point-min))
        (read (current-buffer)))
    ;; Default fallback values
    '((all-notes . 500)
      (journal . 300))))

(defun my/save-daily-goals (goals)
  "Save daily goals to file."
  (with-temp-file my/daily-goals-file
    (insert ";; Daily writing goals - persistent configuration\n")
    (insert ";; Format: ((all-notes . GOAL) (journal . GOAL))\n\n")
    (pp goals (current-buffer))))

(defun my/set-daily-goals ()
  "Interactively set daily writing goals."
  (interactive)
  (let* ((current-goals (my/load-daily-goals))
         (current-all (or (cdr (assoc 'all-notes current-goals)) 500))
         (current-journal (or (cdr (assoc 'journal current-goals)) 300))
         (new-all (read-number 
                   (format "Daily goal for ALL notes (current: %d): " current-all)
                   current-all))
         (new-journal (read-number 
                       (format "Daily goal for JOURNAL (current: %d): " current-journal)
                       current-journal))
         (new-goals `((all-notes . ,new-all)
                      (journal . ,new-journal))))
    (my/save-daily-goals new-goals)
    (message "✅ Daily goals updated: All=%d, Journal=%d" new-all new-journal)
    ;; Refresh dashboard if open
    (when (get-buffer "*dashboard*")
      (with-current-buffer "*dashboard*"
        (dashboard-refresh-buffer)))))

(defun my/format-progress-bar (current goal)
  "Create visual progress bar [████░░░░]."
  (let* ((percentage (if (> goal 0) 
                        (min 100 (/ (* current 100) goal))
                      0))
         (filled (/ percentage 7))  ; 100% = 14 blocks
         (empty (- 14 filled)))
    (concat "["
            (make-string filled ?█)
            (make-string empty ?░)
            "]")))

(defun my/format-number (num)
  "Format number with comma separators: 1234 → 1,234"
  (let ((num-str (number-to-string num)))
    (with-temp-buffer
      (insert num-str)
      (goto-char (point-max))
      (while (> (point) (+ (point-min) 3))
        (backward-char 3)
        (insert ","))
      (buffer-string))))

;; ----- MAIN DASHBOARD FUNCTION -----

(defun my/dashboard-insert-pkm-stats (&optional list-size)
  "Insert PKM statistics with word counts and daily goals."
  (let* ((my-notes-dir (expand-file-name "~/notes"))
         (all-notes (directory-files my-notes-dir nil "\\.org$"))
         (total-notes (length all-notes))
         (today-str (format-time-string "%Y-%m-%d"))
         (notes-today 0)
         (words-today 0)
         (words-total 0)
         
         ;; Categories with word counts
         (fleeting 0)
         (fleeting-words 0)
         (literature 0)
         (literature-words 0)
         (journal 0)
         (journal-words 0)
         (zettel 0)
         (zettel-words 0)
         
         (projects-alist '())
         (well-being-entries '()))
    
    ;; Policz notatki i słowa
    (dolist (file all-notes)
      ;; SKIP lock files (.#filename), auto-saves (#filename#), and hidden files
      (unless (or (string-prefix-p "." file)
              (string-prefix-p "#" file)
              (string-suffix-p "#" file))
	(let ((full-path (expand-file-name file my-notes-dir)))
        
        (with-temp-buffer
          (insert-file-contents full-path)
          
          ;; Count words in this file
          (let ((word-count (count-words (point-min) (point-max))))
            (setq words-total (+ words-total word-count))
            
            ;; Words today
            (when (string-match today-str file)
              (setq words-today (+ words-today word-count)))
            
            ;; Note types + words
            (goto-char (point-min))
            (when (re-search-forward "^#\\+filetags:" nil t)
              (let ((tags (buffer-substring (line-beginning-position) (line-end-position))))
                (cond
                 ((string-match ":fleeting:" tags) 
                  (setq fleeting (1+ fleeting))
                  (setq fleeting-words (+ fleeting-words word-count)))
                 
                 ((string-match ":lektura:" tags) 
                  (setq literature (1+ literature))
                  (setq literature-words (+ literature-words word-count)))
                 
                 ((string-match ":journal:" tags) 
                  (setq journal (1+ journal))
                  (setq journal-words (+ journal-words word-count)))
                 
                 ((string-match ":zettel:" tags) 
                  (setq zettel (1+ zettel))
                  (setq zettel-words (+ zettel-words word-count))))))
            
            ;; Projects
            (goto-char (point-min))
            (when (re-search-forward "^:PROJECT: +\\(.*\\)$" nil t)
              (let* ((project-name (match-string 1))
                     (existing (assoc project-name projects-alist)))
                (if existing
                    (setcdr existing (1+ (cdr existing)))
                  (push (cons project-name 1) projects-alist))))))))
    )
    
    ;; Well-being entries
    (when (file-exists-p (expand-file-name "well-being.org" my-notes-dir))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "well-being.org" my-notes-dir))
        (goto-char (point-min))
        (let ((count 0))
          (while (and (< count 7)
                     (re-search-forward "^\\* \\[\\(.*?\\)\\] \\([0-9]+\\)/10" nil t))
            (push (cons (match-string 1) (match-string 2)) well-being-entries)
            (setq count (1+ count))))))
    
    ;; ===== INSERT INTO DASHBOARD =====
    
    ;; PKM Statistics
    (insert "\n")
    (insert (propertize "📊 PKM Statistics" 
                       'face '(:foreground "#51afef" :weight bold :height 1.2)))
    (insert "\n\n")
    
    ;; Total Notes + words
    (insert (propertize (format "    📝 Total Notes:        %d  (%s słów)\n" 
                               total-notes 
                               (my/format-number words-total))
                       'face '(:foreground "#98be65")))
    
    ;; Categories with word counts
    (insert (format "       ├─ Fleeting:        %d   (%s słów)\n" 
                   fleeting (my/format-number fleeting-words)))
    (insert (format "       ├─ Literature:      %d   (%s słów)\n" 
                   literature (my/format-number literature-words)))
    (insert (format "       ├─ Journal:         %d   (%s słów)\n" 
                   journal (my/format-number journal-words)))
    (insert (format "       └─ Zettel:          %d   (%s słów)\n\n" 
                   zettel (my/format-number zettel-words)))
    
    ;; Today + Daily Goals
    (let* ((goals (my/load-daily-goals))
           (goal-all (or (cdr (assoc 'all-notes goals)) 500))
           (goal-journal (or (cdr (assoc 'journal goals)) 300))
           
           ;; Journal words TODAY only!
           (journal-words-today 0)
           
           (percentage-all (if (> goal-all 0)
                              (min 100 (/ (* words-today 100) goal-all))
                            0))
           (percentage-journal (if (> goal-journal 0)
                                  (min 100 (/ (* journal-words-today 100) goal-journal))
                                0)))
      
      ;; Count journal words TODAY only!
      (dolist (file all-notes)
        (let ((full-path (expand-file-name file my-notes-dir)))
          (when (and (string-match today-str file)
                     (string-match ":journal:" 
                                  (with-temp-buffer
                                    (insert-file-contents full-path)
                                    (buffer-substring (point-min) (min 500 (point-max))))))
            (with-temp-buffer
              (insert-file-contents full-path)
              (setq journal-words-today 
                    (+ journal-words-today 
                       (count-words (point-min) (point-max))))))))
      
      (insert (propertize (format "    📅 Today:              %d notes, %d words\n\n" 
                                 notes-today words-today)
                         'face '(:foreground "#c678dd")))
      
      ;; Daily Goals with progress bars
      (insert (propertize "🎯 Daily Goals" 
                         'face '(:foreground "#da8548" :weight bold :height 1.2)))
      (insert "\n\n")
      
      ;; Goal: All notes
      (insert (format "    All Notes:   %d/%d words   %s %d%%\n" 
                     words-today 
                     goal-all
                     (my/format-progress-bar words-today goal-all)
                     percentage-all))
      
      ;; Goal: Journal (TODAY only!)
      (insert (format "    Journal:     %d/%d words   %s %d%%\n\n" 
                     journal-words-today
                     goal-journal
                     (my/format-progress-bar journal-words-today goal-journal)
                     percentage-journal))
      
      ;; Link to change goals
      (insert "    ")
      (insert-text-button "[g] Change goals"
                         'action (lambda (_) (my/set-daily-goals))
                         'follow-link t
                         'face '(:foreground "#51afef" :underline t))
      (insert "\n\n"))
    
    ;; Projects - LIST
    (when projects-alist
      (insert (propertize "🎯 Projekty badawcze" 
                         'face '(:foreground "#51afef" :weight bold :height 1.2)))
      (insert "\n\n")
      (dolist (proj (seq-take (sort projects-alist (lambda (a b) (> (cdr a) (cdr b)))) 3))
        (let ((status-dots (cond
                            ((> (cdr proj) 10) "●●●")
                            ((> (cdr proj) 5) "●●○")
                            (t "●○○"))))
          (insert (format "    %s  %s (%d notatek)\n" 
                         status-dots
                         (car proj) 
                         (cdr proj)))))
      (insert "\n"))
    
    ;; Well-being
    (when well-being-entries
      (insert (propertize "💚 WELL-BEING (ostatnie 7 dni)" 
                         'face '(:foreground "#98be65" :weight bold :height 1.2)))
      (insert "\n\n")
      (dolist (entry (seq-take well-being-entries 3))
        (let ((date (car entry))
              (score (string-to-number (cdr entry))))
          (insert (format "    %s %s: %s\n" 
                         date
                         (cond
                          ((>= score 8) "😊")
                          ((>= score 6) "🙂")
                          ((>= score 4) "😐")
                          (t "😔"))
                         (cdr entry)))))
      (insert "\n"))
    
    ;; Quick actions
    (insert (propertize "⚡ Quick Actions" 
                       'face '(:foreground "#51afef" :weight bold :height 1.2)))
    (insert "\n\n")
    (insert "    [j] Journal      [b] Quick Note    [z] Zettel      [l] Literature\n")
    (insert "    [p] Filozof      [d] Delete Note   [s] Shortcuts   [c] Full Cockpit\n")
    (insert "    [q] Quit\n\n")))

;; ----- DASHBOARD PACKAGE CONFIGURATION -----

(use-package dashboard
  :ensure t
  :config
  ;; Basic settings
  (setq dashboard-banner-logo-title "📚 Emacs PKM System")
  (setq dashboard-startup-banner 'logo)
  (setq dashboard-center-content nil)
  (setq dashboard-show-shortcuts nil)
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)
  (setq dashboard-icon-type 'all-the-icons)
  (setq dashboard-set-init-info t)

  ;; Exclude config files from recent list globally
  (setq recentf-exclude '("\\.emacs\\.d/"
                          "/elpa/"
                          "\\.git/"
                          "COMMIT_EDITMSG"
                          "\\.elc$"
                          "/modules/"))
  
  ;; Items to show (bookmarks only - recents are custom)
    (setq dashboard-items '((recents . 10)
                          (bookmarks . 5)))
  
  ;; Custom widgets (ORDERED!)
    (setq dashboard-startupify-list '(dashboard-insert-banner
				    dashboard-insert-init-info
                                    dashboard-insert-newline
                                    dashboard-insert-banner-title
                                    dashboard-insert-newline
				    dashboard-insert-items
                                    dashboard-insert-newline
                                    my/dashboard-insert-pkm-stats
                                    dashboard-insert-footer))

    (setq dashboard-item-names '(("Recent Files:" . "📝 Ostatnio otwarte:")
                             ("Bookmarks:" . "⭐ Zakładki:")))
    (setq dashboard-vertically-center-content t)
    (setq dashboard-navigator-buttons
      `(;; Line 1
        ((,(all-the-icons-octicon "mark-github" :height 1.1 :v-adjust 0.0)
          "GitHub"
          "Open GitHub"
          (lambda (&rest _) (browse-url "https://github.com/marcinofulus")))
         ("📚" "Notes Dir" "Open notes" (lambda (&rest _) (dired "~/notes"))))
        ;; Line 2
        ((,(all-the-icons-faicon "book" :height 1.1 :v-adjust 0.0)
          "Philosophy"
          "Browse philosophy books"
          (lambda (&rest _) (find-file "~/notes/filozofia.org"))))))
  ;; Footer quotes
  (setq dashboard-footer-messages 
      '("Free as free speech, free as free Beer"
        "The unexamined life is not worth living — Socrates"
        "I think, therefore I am — Descartes"
        "What we cannot speak about we must pass over in silence — Wittgenstein"
        "Man is condemned to be free — Sartre"
        "The owl of Minerva spreads its wings only with the falling of the dusk — Hegel"
        "There are no facts, only interpretations — Nietzsche"
        "Cogito, ergo sum: I doubt, therefore I think, therefore I am"
        "Being and Nothingness: consciousness is always consciousness of something"
        "The Cave: we see only shadows, not the forms themselves — Plato"
        "Dasein: being-in-the-world, thrown into existence — Heidegger"
        "The absurd is born of confrontation between human need and unreasonable silence — Camus"
        "Hell is other people — Sartre"
        "Whereof one cannot speak, thereof one must be silent — Wittgenstein"
        "The mind is furnished with ideas by experience alone — Locke"))
  
  ;; Keybindings in Dashboard
  (define-key dashboard-mode-map (kbd "j") 'my/denote-journal)
  (define-key dashboard-mode-map (kbd "b") 'my/denote-base)
  (define-key dashboard-mode-map (kbd "z") 'my/denote-zettel)
  (define-key dashboard-mode-map (kbd "l") 'my/denote-lektura)
  (define-key dashboard-mode-map (kbd "p") 'my/denote-filozof)
  (define-key dashboard-mode-map (kbd "d") 'my/denote-delete-note)
  (define-key dashboard-mode-map (kbd "s") 'my/denote-shortcuts)
  (define-key dashboard-mode-map (kbd "c") 'my/denote-cockpit)
  (define-key dashboard-mode-map (kbd "g") 'my/set-daily-goals)
  (define-key dashboard-mode-map (kbd "r") 'dashboard-refresh-buffer)
  (define-key dashboard-mode-map (kbd "q") 'quit-window)


  
  ;; Setup Dashboard
  (dashboard-setup-startup-hook))

(provide '01-packages)
;;; 01-packages.el ends here
