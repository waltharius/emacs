;;; 13-project-management.el --- Project management with Org-agenda and Kanban -*- lexical-binding: t; -*-
;;
;; Description: Org-agenda configuration, Org-kanban boards.
;;              Org-super-agenda grouping, time tracking
;;
;;; Commentary:
;;
;; This module enables professional project management capabilities:
;; - Org-agenda for centralized task view across all projects
;; - Org-kanban for visual board management
;; - Org-super-agenda for automatic task grouping
;; - Time tracking with clock-in/clock-out
;; - Custom agenda commands for common workflows
;;
;; Usage:
;;   C-c a     → Open agenda dispatcher
;;   C-c a a   → Weekly agenda view
;;   C-c a t   → Global TODO list
;;   C-c a p   → All projects overview
;;   C-c C-x C-i → Clock in (start timer on task)
;;   C-c C-x C-o → Clock out (stop timer)
;;
;;; Code:

;; ============================================================
;; ORG-AGENDA: Central task management
;; ============================================================

(use-package org-agenda
  :ensure nil  ; Built-in
  :demand t
  :custom
  ;; Agenda files: All project files tracked by the system
  (org-agenda-files (list my/notes-dir))
  
  ;; Include files matching these patterns
  (org-agenda-file-regexp ".*__project\\.org$")
  
  ;; Appearance
  (org-agenda-window-setup 'current-window)
  (org-agenda-restore-windows-after-quit t)
  (org-agenda-span 7)  ; Show 7 days by default
  (org-agenda-start-on-weekday 1)  ; Start week on Monday
  
  ;; Task display
  (org-agenda-todo-ignore-scheduled 'future)
  (org-agenda-todo-ignore-deadlines 'far)
  (org-agenda-tags-todo-honor-ignore-options t)
  
  ;; Time grid
  (org-agenda-time-grid
   '((daily today require-timed)
     (800 1000 1200 1400 1600 1800 2000)
     " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"))
  
  ;; Sorting
  (org-agenda-sorting-strategy
   '((agenda habit-down time-up priority-down category-keep)
     (todo priority-down category-keep)
     (tags priority-down category-keep)
     (search category-keep)))
  
  :config
  ;; Custom agenda commands
  (setq org-agenda-custom-commands
        '(("p" "All Projects Overview"
           ((tags "project"
                  ((org-agenda-overriding-header "━━━ 📋 ACTIVE PROJECTS ━━━")
                   (org-agenda-prefix-format "  %i %?-12t% s")
                   (org-agenda-sorting-strategy '(priority-down))))
            (todo "NEXT"
                  ((org-agenda-overriding-header "\n━━━ ⚡ NEXT ACTIONS ━━━")
                   (org-agenda-prefix-format "  %i %-12:c %s")))
            (todo "WAITING"
                  ((org-agenda-overriding-header "\n━━━ ⏸️  WAITING FOR ━━━")
                   (org-agenda-prefix-format "  %i %-12:c %s")))
            (todo "INPROGRESS"
                  ((org-agenda-overriding-header "\n━━━ 🔨 IN PROGRESS ━━━")
                   (org-agenda-prefix-format "  %i %-12:c %s")))))
          
          ("d" "Daily Agenda + Next Actions"
           ((agenda "" ((org-agenda-span 1)
                       (org-agenda-overriding-header "━━━ 📅 TODAY ━━━")))
            (todo "INPROGRESS"
                  ((org-agenda-overriding-header "\n━━━ 🔨 IN PROGRESS ━━━")))
            (todo "NEXT"
                  ((org-agenda-overriding-header "\n━━━ ⚡ NEXT ACTIONS ━━━")
                   (org-agenda-max-entries 5)))))
          
          ("w" "Weekly Review"
           ((agenda "" ((org-agenda-span 7)
                       (org-agenda-overriding-header "━━━ 📅 THIS WEEK ━━━")))
            (todo "DONE"
                  ((org-agenda-overriding-header "\n━━━ ✅ COMPLETED ━━━")
                   (org-agenda-skip-function
                    '(org-agenda-skip-entry-if 'notregexp "CLOSED: \\[.*\\]"))))))
          
          ("r" "PKM Refactoring Project"
           ((tags "pkm+refactoring"
                  ((org-agenda-overriding-header "━━━ 🔧 PKM REFACTORING ━━━")))
            (agenda "" ((org-agenda-span 3)
                       (org-agenda-files '("~/notes/20251009--PKM-refactoring__project.org"))))))))
  
  :bind (("C-c a" . org-agenda)
         :map org-agenda-mode-map
         ("j" . org-agenda-next-line)
         ("k" . org-agenda-previous-line)))

;; ============================================================
;; ORG-SUPER-AGENDA: Smart task grouping
;; ============================================================

(use-package org-super-agenda
  :ensure t
  :after org-agenda
  :demand t
  :custom
  (org-super-agenda-groups
   '((:name "⚠️  Overdue"
      :deadline past
      :order 1)
     
     (:name "🔥 Urgent & Important"
      :priority "A"
      :order 2)
     
     (:name "📅 Due Today"
      :deadline today
      :order 3)
     
     (:name "🔨 In Progress"
      :todo "INPROGRESS"
      :order 4)
     
     (:name "⚡ Next Actions"
      :todo "NEXT"
      :order 5)
     
     (:name "📋 Phase 1: Code Quality"
      :tag "phase-1"
      :order 6)
     
     (:name "🔧 Phase 2: Refactoring"
      :tag "phase-2"
      :order 7)
     
     (:name "✨ Phase 3: New Features"
      :tag "phase-3"
      :order 8)
     
     (:name "⏸️  Waiting"
      :todo "WAITING"
      :order 9)
     
     (:name "📌 Decisions Needed"
      :tag "decision"
      :order 10)
     
     (:name "🗓️  Scheduled"
      :scheduled future
      :order 11)
     
     (:name "📝 Standard Tasks"
      :priority<= "C"
      :order 12)))
  
  :config
  (org-super-agenda-mode 1))

;; ============================================================
;; ORG-KANBAN: Visual board management
;; ============================================================

(use-package org-kanban
  :ensure t
  :after org
  :commands (org-kanban/initialize
             org-kanban/shift
             org-kanban/next
             org-kanban/prev)
  :custom
  (org-kanban/prev-key "H")  ; Move task left on kanban
  (org-kanban/next-key "L")) ; Move task right on kanban

;; Keybinding for kanban
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c k") 'org-kanban/initialize))

;; ============================================================
;; TIME TRACKING: Clock in/out
;; ============================================================

(use-package org-clock
  :ensure nil  ; Built-in
  :custom
  ;; Save clock history across sessions
  (org-clock-persist t)
  (org-clock-persist-file (expand-file-name ".org-clock-save.el" user-emacs-directory))
  
  ;; Clock behavior
  (org-clock-in-resume t)  ; Resume interrupted clock
  (org-clock-into-drawer t)  ; Store clocks in :LOGBOOK: drawer
  (org-clock-out-remove-zero-time-clocks t)
  
  ;; Idle time detection
  (org-clock-idle-time 15)  ; Ask after 15 min idle
  
  ;; Reports
  (org-clock-report-include-clocking-task t)
  
  :config
  (org-clock-persistence-insinuate)
  
  ;; Clock modeline - show current task
  (setq org-clock-clocked-in-display 'mode-line))

;; ============================================================
;; CUSTOM STATISTICS FUNCTIONS
;; ============================================================

(defun my/org-project-completion-percentage ()
  "Calculate completion percentage for current project.
Returns percentage as integer (0-100)."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((total 0)
          (done 0))
      (while (re-search-forward org-todo-line-regexp nil t)
        (setq total (1+ total))
        (when (member (match-string 2) org-done-keywords)
          (setq done (1+ done))))
      (if (zerop total)
          0
        (let ((pct (/ (* 100 done) total)))
          (message "Project completion: %d%% (%d/%d tasks)" pct done total)
          pct)))))

(defun my/org-time-summary ()
  "Show time summary for current project.
Displays total clocked time and estimate vs actual."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((total-clocked 0)
          (total-estimate 0))
      ;; Calculate totals
      (org-clock-sum)
      (setq total-clocked org-clock-file-total-minutes)
      
      ;; Parse effort estimates
      (while (re-search-forward "^[ \t]*:Effort:[ \t]+\\([0-9]+:[0-9]+\\)" nil t)
        (let ((effort (match-string 1)))
          (when (string-match "\\([0-9]+\\):\\([0-9]+\\)" effort)
            (setq total-estimate
                  (+ total-estimate
                     (+ (* 60 (string-to-number (match-string 1 effort)))
                        (string-to-number (match-string 2 effort))))))))
      
      (message "Time: %dh %dm clocked | %dh %dm estimated | %s"
               (/ total-clocked 60)
               (mod total-clocked 60)
               (/ total-estimate 60)
               (mod total-estimate 60)
               (if (> total-clocked total-estimate)
                   (format "%.0f%% over estimate"
                           (* 100.0 (/ (- total-clocked total-estimate)
                                      (float total-estimate))))
                 "on track")))))

;; ============================================================
;; HELPER FUNCTIONS
;; ============================================================

(defun my/open-project-file ()
  "Open project file interactively from list of available projects."
  (interactive)
  (let* ((all-files (directory-files my/notes-dir nil "\\.org$"))
         ;; Filter files containing __project OR :project: tag
         (project-files (seq-filter
                         (lambda (f)
                           (or (string-match-p "__project" f)
                               (string-match-p "__.*project" f)))
                         all-files)))
    
    (if (zerop (length project-files))
        (message "No project files found. Create one with C-c n p")
      
      ;; Extract clean names for completion
      (let* ((project-choices
              (mapcar
               (lambda (filename)
                 ;; Extract title from --TITLE__ pattern
                 (if (string-match "--\\([^_]+\\)" filename)
                     (replace-regexp-in-string "-" " " (match-string 1 filename))
                   filename))
               project-files))
             
             ;; Create alist: (display-name . filename)
             (project-alist (cl-mapcar #'cons project-choices project-files))
             
             ;; Let user choose
             (choice (completing-read "Project: " project-choices nil t))
             
             ;; Get corresponding filename
             (selected-file (cdr (assoc choice project-alist))))
        
        ;; Open file
        (if selected-file
            (find-file (expand-file-name selected-file my/notes-dir))
          (message "File not found: %s" choice))))))

;; ============================================================
;; TODO KEYWORDS & PRIORITIES
;; ============================================================

;; Set default TODO keywords for all org files
(setq org-todo-keywords
      '((sequence "TODO(t)" "NEXT(n)" "INPROGRESS(i)" "WAITING(w)" "|"
                  "DONE(d)" "CANCELLED(c)")))

;; Colors for TODO states
(setq org-todo-keyword-faces
      '(("TODO" . (:foreground "red" :weight bold))
        ("NEXT" . (:foreground "orange" :weight bold))
        ("INPROGRESS" . (:foreground "yellow" :weight bold))
        ("WAITING" . (:foreground "magenta" :weight bold))
        ("DONE" . (:foreground "green" :weight bold))
        ("CANCELLED" . (:foreground "gray" :weight bold))))

;; Priorities
(setq org-priority-faces
      '((?A . (:foreground "red" :weight bold))
        (?B . (:foreground "orange"))
        (?C . (:foreground "gray"))))

;; ============================================================
;; ORG-COLUMNS: Spreadsheet view
;; ============================================================

;; Column view format
(setq org-columns-default-format
      "%50ITEM(Task) %TODO %3PRIORITY %10Effort(Estimate){:} %10CLOCKSUM(Clocked)")

;; Effort estimates
(setq org-global-properties
      '(("Effort_ALL" . "0:15 0:30 1:00 2:00 4:00 8:00 16:00 24:00")))

;; ============================================================
;; AUTO-UPDATE :MODIFIED: PROPERTY
;; ============================================================

(defun my/org-update-modified-property ()
  "Update :MODIFIED: property in current heading to current timestamp."
  (interactive)
  (when (and (eq major-mode 'org-mode)
             (org-entry-get nil "CREATED")) ; Only if heading has :CREATED:
    (org-entry-put nil "MODIFIED"
                   (format-time-string "[%Y-%m-%d %a %H:%M]"))))

;; Auto-update on save (only for project files)
(defun my/org-auto-update-modified ()
  "Update MODIFIED property on save if file is a project."
  (when (and (eq major-mode 'org-mode)
             (buffer-file-name)
             (string-match-p "__project\\.org$" (buffer-file-name)))
    (save-excursion
      (goto-char (point-min))
      ;; Find first heading with :CREATED: property
      (when (re-search-forward "^\\*+ " nil t)
        (my/org-update-modified-property)))))

(add-hook 'before-save-hook 'my/org-auto-update-modified)

;; ---- Transient Menu
(require 'transient)

(transient-define-prefix my/project-menu ()
  "Project management menu with live preview"
  ["Project Actions"
   ["Create & Open"
    ("n" "New project" my/denote-create-project)
    ("o" "Open project" my/open-project-file)
    ("f" "Find by category" my/denote-find-by-property)]
   ["Statistics"
    ("%" "Completion %" my/org-project-completion-percentage)
    ("t" "Time summary" my/org-time-summary)
    ("s" "Project stats" my/denote-project-stats)]
   ["Agenda & Kanban"
    ("a" "Agenda" org-agenda)
    ("k" "Kanban board" org-kanban/initialize)]
   ["Time Tracking"
    ("i" "Clock in" org-clock-in)
    ("o" "Clock out" org-clock-out)
    ("r" "Clock report" org-clock-report)]]
  ["Navigation"
   ("q" "Quit" transient-quit-one)])

;; Keybinding
(global-set-key (kbd "C-c p") 'my/project-menu)
(provide '13-project-management)
;;; 13-project-management.el ends here
