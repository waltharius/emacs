;;; 05c-denote-statistics.el --- Denote statistics and dashboards -*- lexical-binding: t; -*-
;;
;; Description: Note counting, word statistics, project tracking, and dashboards
;;
;;; Code:
;;; 05c-denote-statistics.el --- Denote statistics and dashboards -*- lexical-binding: t; -*-
;;
;; Description: Note counting, word statistics, project tracking, and dashboards
;;
;; TODO (improvements for later):
;; - [ ] Better project tracking (auto-detect projects from tags)
;; - [ ] Weekly/monthly statistics (not just today)
;; - [ ] Graph visualization (sparklines?)
;; - [ ] Export statistics to CSV/JSON
;; - [ ] Compare stats between time periods
;; - [ ] Streak tracking (consecutive days writing)
;; - [ ] Better dashboard formatting (tables?)
;; - [ ] Performance optimization (cache more aggressively)
;; - [ ] Notifications when goal reached (desktop notification?)
;; - [ ] Integration with org-habit for writing habits
;;; 05d-denote-wellbeing.el --- Well-being & mood tracking -*- lexical-binding: t; -*-
;;
;; Description: Scientific mood tracking with visualizations
;;
;; TRACKING MODEL (Circumplex Model - Russell 1980):
;;   - Valence (1-10): negative ← → positive
;;   - Arousal (1-10): low energy ← → high energy
;;   - Emotions: joy, anxiety, sadness, calm, excitement, boredom...
;;   - Context: activity, people, location
;;
;; TODO - Visualization & Analytics (research-backed):
;; - [ ] TIER 1: Core Visualizations
;;   - [ ] Time-series line graphs (7/30/90 days) [JMIR Mental Health 2022]
;;   - [ ] Calendar heatmaps (emoji-based mood calendar)
;;   - [ ] Circumplex scatter plot (valence × arousal)
;;   - [ ] Distribution histograms (mood frequency)
;;
;; - [ ] TIER 2: Pattern Detection
;;   - [ ] Auto-correlations (sleep, exercise, social → mood)
;;   - [ ] Activity-mood associations ("feel best after X")
;;   - [ ] Time-of-day patterns (morning vs evening mood)
;;   - [ ] Weekly/monthly trends (moving averages)
;;
;; - [ ] TIER 3: Advanced Analytics
;;   - [ ] Emotional granularity tracking (27 emotions, Barrett 2007)
;;   - [ ] Mood stability metrics (standard deviation over time)
;;   - [ ] Streak tracking (consecutive days with positive mood)
;;   - [ ] Regression to identify triggers
;;
;; - [ ] TIER 4: Clinical/Export Features
;;   - [ ] PDF report generation (graphs + summary)
;;   - [ ] CSV export for therapist review
;;   - [ ] Standardized questionnaires (PHQ-9, GAD-7 integration)
;;
;; - [ ] TIER 5: UX Improvements
;;   - [ ] Quick entry widget (3 taps: mood + energy + save)
;;   - [ ] Smart prompts ("How do you feel after [activity]?")
;;   - [ ] Voice entry support (org-mode audio notes)
;;   - [ ] Emacs notifications for check-ins
;;
;; RESEARCH SOURCES:
;;   - JMIR Mental Health 2022: Data visualization preferences
;;   - Lisa Feldman Barrett: Emotional granularity theory
;;   - Quantified Self community: Best practices
;;   - NIH study on mood tracking apps (2021)
;;
;;; Code:

;; ============================================================
;; CONFIGURATION
;; ============================================================

(defvar my/daily-word-goal 3000
  "Dzienny cel słów do napisania.")

(defvar my/project-daily-goals nil
  "Dzienne cele słów dla projektów: '((\"tag\" . liczba-słów) ...)
Przykład: '((\"arystoteles\" . 2000) (\"moja-ksiazka\" . 1500))")

;; ============================================================
;; DASHBOARD CACHE (Performance optimization)
;; ============================================================

(defvar my/dashboard-cache nil
  "Plist cache for expensive dashboard calculations.")

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
  (message "Dashboard cache invalidated"))

;; ============================================================
;; WORD & FILE COUNTING
;; ============================================================

(defun my/denote-count-words-all ()
  "Count words in all Denote files (with cache)."
  (interactive)
  (if (my/dashboard-cache-valid-p)
      (plist-get my/dashboard-cache :total-words)
    (let ((total-words 0)
          (file-count 0))
      (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count))))
      
      (setq my/dashboard-cache (plist-put my/dashboard-cache :total-words total-words))
      (setq my/dashboard-cache (plist-put my/dashboard-cache :total-files file-count))
      (setq my/dashboard-cache (plist-put my/dashboard-cache :last-update (float-time)))
      
      (message "Statystyki: %d plików, %d słów" file-count total-words)
      total-words)))

(defun my/denote-count-words-today ()
  "Count words in notes created TODAY."
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
    (message "Dzisiaj: %d plików, %d słów" file-count total-words)))

;; ============================================================
;; WRITING GOALS
;; ============================================================

(defun my/denote-writing-goal ()
  "Check progress towards daily writing goal."
  (interactive)
  (let* ((today (format-time-string "%Y-%m-%d"))
         (total-words 0)
         (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (when (string-match-p today file)
        (with-temp-buffer
          (insert-file-contents file)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    
    (let* ((progress (* 100.0 (/ (float total-words) my/daily-word-goal)))
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

(defun my/denote-project-stats ()
  "Count words in selected project by tag."
  (interactive)
  (let* ((all-tags (delete-dups
                    (apply #'append
                           (mapcar (lambda (file)
                                     (denote-extract-keywords-from-path file))
                                   (denote-directory-files)))))
         (project-tag (completing-read "Tag projektu: " all-tags))
         (total-words 0)
         (file-count 0))
    (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward (format "\\b%s\\b" (regexp-quote project-tag)) nil t)
          (setq total-words (+ total-words (count-words (point-min) (point-max))))
          (setq file-count (1+ file-count)))))
    (message "Projekt '%s': %d plików, %d słów" project-tag file-count total-words)))

(defun my/denote-project-goal ()
  "Check progress towards daily project goal."
  (interactive)
  (if (null my/project-daily-goals)
      (message "⚠ Brak projektów! Ustaw 'my/project-daily-goals' w 05c-denote-statistics.el")
    (let* ((all-tags (mapcar #'car my/project-daily-goals))
           (project-tag (completing-read "Tag projektu: " all-tags))
           (goal (or (cdr (assoc project-tag my/project-daily-goals)) 1000))
           (today (format-time-string "%Y-%m-%d"))
           (total-words 0)
           (file-count 0))
      
      (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
        (when (string-match-p today file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (when (re-search-forward (format "\\b%s\\b" (regexp-quote project-tag)) nil t)
              (setq total-words (+ total-words (count-words (point-min) (point-max))))
              (setq file-count (1+ file-count))))))
      
      (let* ((progress (* 100.0 (/ (float total-words) goal)))
             (remaining (- goal total-words))
             (emoji (cond ((>= progress 100) "🎉")
                          ((>= progress 75) "🔥")
                          ((>= progress 50) "💪")
                          ((>= progress 25) "📝")
                          (t "🌱"))))
        (message "%s Projekt '%s': %d/%d słów (%.1f%%) | Brakuje: %d"
                 emoji project-tag total-words goal progress
                 (max 0 remaining))))))

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
      (insert "║                📊 STATS               ║\n")
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
      (let* ((today (format-time-string "%Y-%m-%d"))
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
        (let* ((goal my/daily-word-goal)
               (progress (* 100.0 (/ (float today-words) my/daily-word-goal)))
               (emoji (cond ((>= progress 100) "🎉")
                            ((>= progress 75) "🔥")
                            ((>= progress 50) "💪")
                            (t "📝"))))
          (insert (format "%s Cel dzienny: %d/%d (%.1f%%)\n" emoji today-words goal progress))))
      
      ;; Projects (only if configured)
      (when my/project-daily-goals
        (insert "\n╔═══════════════════════════════════════╗\n")
        (insert "║               📁 PROJEKTY             ║\n")
        (insert "╚═══════════════════════════════════════╝\n\n")
        (dolist (project my/project-daily-goals)
          (let* ((tag (car project))
                 (goal (cdr project))
                 (today (format-time-string "%Y-%m-%d"))
                 (words 0))
            (dolist (file (directory-files-recursively my-notes-dir "\\.org$"))
              (when (string-match-p today file)
                (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (when (re-search-forward (format "\\b%s\\b" (regexp-quote tag)) nil t)
                    (setq words (+ words (count-words (point-min) (point-max))))))))
            (let* ((progress (* 100.0 (/ (float words) goal)))
                   (emoji (cond ((>= progress 100) "🎉")
                                ((>= progress 50) "💪")
                                (t "📝"))))
              (insert (format "%s %s: %d/%d (%.0f%%)\n" emoji tag words goal progress))))))
      
      (insert "\n\n[r] Odśwież | [q] Zamknij\n")
      (goto-char (point-min))
      (read-only-mode 1)
      (local-set-key (kbd "r") 'my/denote-dashboard)
      (local-set-key (kbd "q") 'quit-window)
      (switch-to-buffer buffer-name))))

(provide '05c-denote-statistics)
;;; 05c-denote-statistics.el ends here
