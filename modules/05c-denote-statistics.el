;;; 05c-denote-statistics.el --- Denote statistics and dashboards -*- lexical-binding: t; -*-
;;
;; Description: Note counting, word statistics, project tracking, and dashboards
;;
;;; Code:

;; ============================================================
;; DASHBOARD CACHE (Performance optimization)
;; ============================================================

(defvar my/dashboard-cache nil
  "Plist cache for expensive dashboard calculations.
Format: (:total-words NUM :total-files NUM :last-update TIMESTAMP)")

(defvar my/dashboard-cache-ttl 300
  "Cache time-to-live in seconds (5 minutes).")

(defun my/dashboard-cache-valid-p ()
  "Check if dashboard cache is still valid."
  (and my/dashboard-cache
       (plist-get my/dashboard-cache :last-update)
       (< (- (float-time) (plist-get my/dashboard-cache :last-update))
          my/dashboard-cache-ttl)))

(defun my/dashboard-invalidate-cache ()
  "Invalidate dashboard cache - force recalculation."
  (interactive)
  (setq my/dashboard-cache nil)
  (message "Dashboard cache invalidated - next open will recalculate"))

;; ============================================================
;; WORD & FILE COUNTING
;; ============================================================

(defun my/denote-count-words-all ()
  "Count words in all Denote files (with cache).
Cache valid for 5 minutes. Use `M-x my/dashboard-invalidate-cache' to force refresh."
  (interactive)
  (if (my/dashboard-cache-valid-p)
      ;; Return cached value
      (plist-get my/dashboard-cache :total-words)
    ;; Cache invalid - recalculate
    (let ((total-words 0)
          (total-chars 0)
          (file-count 0))
      (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq total-chars (+ total-chars (- (point-max) (point-min))))
          (setq file-count (1+ file-count))))
      
      ;; Update cache
      (setq my/dashboard-cache (plist-put my/dashboard-cache :total-words total-words))
      (setq my/dashboard-cache (plist-put my/dashboard-cache :total-files file-count))
      (setq my/dashboard-cache (plist-put my/dashboard-cache :last-update (float-time)))
      
      (message "Dashboard cache refreshed - %d files, %d words" file-count total-words)
      (message "Statystyki: %d plików, %d słów, %d znaków" file-count total-words total-chars)
      total-words)))

(defun my/denote-count-words-today ()
  "Count words in notes created TODAY."
  (interactive)
  (let ((today (format-time-string "%Y-%m-%d"))
        (total-words 0)
        (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)  ; Check if date in filename is today
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (message "Dzisiaj: %d plików, %d słów" file-count total-words)))

;; ============================================================
;; WRITING GOALS
;; ============================================================

(defvar my/daily-word-goal 3000
  "Dzienny cel słów do napisania.")

(defun my/denote-writing-goal ()
  "Check progress towards daily writing goal."
  (interactive)
  (let ((today (format-time-string "%Y-%m-%d"))
        (total-words 0)
        (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    
    (let ((progress (* 100.0 (/ (float total-words) my/daily-word-goal)))
          (remaining (- my/daily-word-goal total-words))
          (emoji (cond ((>= progress 100) "🎉")
                       ((>= progress 75) "🔥")
                       ((>= progress 50) "💪")
                       ((>= progress 25) "📝")
                       (t "🌱"))))
      (message "%s Cel: %d/%d słów (%.1f%%) | Brakuje: %d"
               emoji total-words my/daily-word-goal progress
               (max 0 remaining)))))

;; ============================================================
;; PROJECT STATISTICS
;; ============================================================

(defvar my/project-daily-goals
  '(("arystoteles" . 2000))
  "Dzienne cele słów dla projektów: (tag . liczba-słów)...")

(defun my/denote-project-stats ()
  "Count words in selected project by tag."
  (interactive)
  (let ((project-tag (completing-read "Tag projektu: " '("arystoteles" "kant" "hume" "projekt")))
        (total-words 0)
        (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward (format "%s" project-tag) nil t)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (message "Projekt '%s': %d plików, %d słów" project-tag file-count total-words)))

(defun my/denote-project-goal ()
  "Check progress towards daily project goal."
  (interactive)
  (let* ((project-tag (completing-read "Tag projektu: " (mapcar #'car my/project-daily-goals)))
         (goal (or (cdr (assoc project-tag my/project-daily-goals)) 1000))
         (today (format-time-string "%Y-%m-%d"))
         (total-words 0)
         (file-count 0))
    
    ;; Count words in files with TODAY's date AND project tag
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward (format "%s" project-tag) nil t)
            (setq total-words (+ total-words (count-words (point-min) (point-max))))
            (setq file-count (1+ file-count))))))
    
    (let ((progress (* 100.0 (/ (float total-words) goal)))
          (remaining (- goal total-words))
          (emoji (cond ((>= progress 100) "🎉")
                       ((>= progress 75) "🔥")
                       ((>= progress 50) "💪")
                       ((>= progress 25) "📝")
                       (t "🌱"))))
      (message "%s Projekt '%s': %d/%d słów (%.1f%%) | Brakuje: %d"
               emoji project-tag total-words goal progress
               (max 0 remaining)))))

;; ============================================================
;; DASHBOARDS
;; ============================================================

(defun my/denote-dashboard ()
  "Show live dashboard with statistics."
  (interactive)
  (let ((buffer-name "*Denote Dashboard*"))
    (with-current-buffer (get-buffer-create buffer-name)
      (read-only-mode -1)
      (erase-buffer)
      
      (insert "\n")
      (insert "╔═══════════════════════════════════════╗\n")
      (insert "║         📊 STATS                      ║\n")
      (insert "╚═══════════════════════════════════════╝\n\n")
      
      ;; Global stats
      (insert "** Statystyki globalne\n")
      (let ((total-words 0)
            (total-files 0))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (with-temp-buffer
            (insert-file-contents file)
            (setq total-words (+ total-words (count-words (point-min) (point-max))))
            (setq total-files (1+ total-files))))
        (insert (format "Wszystkie notatki: %d plików, %d słów\n" total-files total-words)))
      
      ;; Today stats
      (let ((today (format-time-string "%Y-%m-%d"))
            (today-words 0)
            (today-files 0))
        (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
          (when (string-match-p today file)
            (with-temp-buffer
              (insert-file-contents file)
              (setq today-words (+ today-words (count-words (point-min) (point-max))))
              (setq today-files (1+ today-files)))))
        (insert (format "Dzisiaj: %d plików, %d słów\n" today-files today-words))
        
        ;; Daily goal
        (let ((goal my/daily-word-goal)
              (progress (* 100.0 (/ (float today-words) my/daily-word-goal)))
              (emoji (cond ((>= progress 100) "🎉")
                           ((>= progress 75) "🔥")
                           ((>= progress 50) "💪")
                           (t "📝"))))
          (insert (format "%s Cel dzienny: %d/%d (%.1f%%)\n" emoji today-words goal progress))))
      
      ;; Projects
      (insert "\n╔═══════════════════════════════════════╗\n")
      (insert "║        📁 PROJEKTY                     ║\n")
      (insert "╚═══════════════════════════════════════╝\n\n")
      (dolist (project my/project-daily-goals)
        (let ((tag (car project))
              (goal (cdr project))
              (today (format-time-string "%Y-%m-%d"))
              (words 0))
          (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
            (when (string-match-p today file)
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (when (re-search-forward (format "%s" tag) nil t)
                  (setq words (+ words (count-words (point-min) (point-max))))))))
          (let ((progress (* 100.0 (/ (float words) goal)))
                (emoji (cond ((>= progress 100) "🎉")
                             ((>= progress 50) "💪")
                             (t "📝"))))
            (insert (format "%s %s: %d/%d (%.0f%%)\n" emoji tag words goal progress)))))
      
      (insert "\n\n[r] Odśwież | [q] Zamknij\n")
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "r") 'my/denote-dashboard)
      (local-set-key (kbd "q") 'quit-window)
      (switch-to-buffer buffer-name))))

(defun my/denote-cockpit ()
  "Interactive cockpit for note management."
  (interactive)
  ;; This is a more complex dashboard - simplified for now
  (my/denote-dashboard))

(provide '05c-denote-statistics)
;;; 05c-denote-statistics.el ends here
