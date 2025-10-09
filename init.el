;;; init.el --- Modular Emacs configuration for Denote note-taking  -*- lexical-binding: t; -*-
;;
;; Author: Marcin
;; Created: 2025-10-03
;; Description: Modułowa konfiguracja Emacsa z systemem notatek Denote
;;
;; Struktura:
;;   - modules/00-variables.el        : Plik ze wszystkimi zmiennymi. MUSI być na początku!!
;;   - modules/01-packages.el         : Zarządzanie pakietami
;;   - modules/02-spelling.el         : Sprawdzanie pisowni i gramatyki
;;   - modules/03-ui.el               : Ustawienia interfejsu
;;   - modules/04-denote-core.el      : Konfiguracja Denote
;;   - modules/05-denote-functions.el : Custom funkcje Denote
;;   - modules/06-keybindings.el      : Skróty klawiszowe
;;   - modules/07-git.el              : Konfiguracja git
;;   - modules/08-modern-conveniences : Usprawnienia Emacs bez pisania kodu
;;   - modules/09-themes-gallery      : Galeria szablonów zmieniających wygląd Emacs
;;   - modules/10-org-formatting      : Skróty do formatowania tekstu i inne przydatne bajery z tekstem związane
;;   - modules/11-org-journal         : Integracja z calendar i nawigacja
;;   - modules/13-project-management  : Org-agenda, kanban, time tracking
;;   - modules/14-transient-menus     : Unified transient menus
;;
;;; Code:

;; ============================================================
;; PERFORMANCE MONITORING SETUP
;; ============================================================

;; Store actual startup time (before anything loads)
(defvar my/emacs-start-time (current-time)
  "Time when Emacs started loading init.el.")

;; Create logs directory
(unless (file-exists-p (concat user-emacs-directory "logs/"))
  (make-directory (concat user-emacs-directory "logs/")))

;; Log file with timestamp
(defvar my/startup-log-file
  (concat user-emacs-directory
          "logs/startup-"
          (format-time-string "%Y%m%d-%H%M%S")
          ".log")
  "Log file for this session's startup benchmark.")

;; Benchmark data storage
(defvar my/benchmark-data nil
  "List of (module-name . load-time) pairs.")

;; Module loading with benchmark
(defun my/load-module (module-name)
  "Load MODULE-NAME from ~/.emacs.d/modules/ and benchmark it."
  (let* ((module-file (expand-file-name
                       (concat "modules/" module-name)
                       user-emacs-directory))
         (start-time (current-time)))
    (if (file-exists-p module-file)
        (progn
          (message "[Loading] %s..." module-name)
          (load-file module-file)
          (let* ((end-time (current-time))
                 (elapsed (float-time (time-subtract end-time start-time))))
            (push (cons module-name elapsed) my/benchmark-data)
            (message "[✓ %.3fs] %s" elapsed module-name)))
      (message "[ERROR] Module %s not found!" module-name))))

;; Save benchmark log
(defun my/save-benchmark-log ()
  "Write detailed startup benchmark to log file."
  (let ((total-time (float-time (time-subtract (current-time) my/emacs-start-time)))
        (official-time (string-to-number (car (split-string (emacs-init-time))))))
    (with-temp-buffer
      (insert "╔═══════════════════════════════════════════════════════════╗\n")
      (insert (format "║  EMACS STARTUP BENCHMARK - %s  ║\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")))
      (insert "╚═══════════════════════════════════════════════════════════╝\n\n")
      
      ;; Total times
      (insert (format "Emacs init-time (official):  %.3fs\n" official-time))
      (insert (format "Actual measured time:        %.3fs\n" total-time))
      (insert (format "Missing time (UI/desktop):   %.3fs (%.0f%%)\n\n"
                      (- total-time official-time)
                      (* 100 (/ (- total-time official-time) total-time))))
      
      ;; Module breakdown
      (insert "Module load times (sorted by duration):\n")
      (insert "─────────────────────────────────────────────────────────\n")
      (dolist (entry (sort my/benchmark-data (lambda (a b) (> (cdr a) (cdr b)))))
        (insert (format "  %-45s %6.3fs  (%3.0f%%)\n"
                        (car entry)
                        (cdr entry)
                        (* 100 (/ (cdr entry) total-time)))))
      
      ;; Summary
      (insert "\n")
      (insert (format "Total modules loaded:   %d\n" (length my/benchmark-data)))
      (insert (format "Average per module:     %.3fs\n"
                      (/ (apply '+ (mapcar 'cdr my/benchmark-data))
                         (float (length my/benchmark-data)))))
      (insert (format "\nLog saved to: %s\n" my/startup-log-file))
      
      (write-region (point-min) (point-max) my/startup-log-file)
      (message "📊 Startup benchmark saved: %s" (file-name-nondirectory my/startup-log-file)))))

;; Hook to save log after init
(add-hook 'after-init-hook 'my/save-benchmark-log)

;; Command to view last log
(defun my/view-startup-log ()
  "Open the most recent startup log file."
  (interactive)
  (let* ((logs-dir (concat user-emacs-directory "logs/"))
         (logs (directory-files logs-dir t "startup-.*\\.log$"))
         (latest (car (sort logs 'string>))))
    (if latest
        (find-file latest)
      (message "No startup logs found in %s" logs-dir))))

;; ============================================================
;; PERFORMANCE: Garbage collection optimization (startup only)
;; ============================================================

(setq gc-cons-threshold most-positive-fixnum)  ; Disable GC during startup

;; Reset GC after startup
(add-hook 'after-init-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))  ; 16MB (reasonable)
            (message "GC threshold reset to 16MB")))

;; ============================================================
;; CRITICAL: Load fresh .el files (prevent cache issues)
;; ============================================================

(setq load-prefer-newer t)

;; ============================================================
;; USE-PACKAGE STATISTICS (must be BEFORE packages load!)
;; ============================================================

(setq use-package-compute-statistics t
      use-package-verbose t)  ; Show loading messages

;; ============================================================
;; RECENTF MODE (before modules)
;; ============================================================

(recentf-mode 1)
(setq recentf-max-saved-items 100
      recentf-auto-cleanup 'never
      recentf-exclude '("\\.git/"
                        "COMMIT_EDITMSG"
                        "\\.elc$"
                        "/elpa/"
                        "^/tmp/"
                        "^#.*#$"        ; Auto-save files
                        "^\\.#"))       ; Lock files

;; ============================================================
;; DESKTOP RESTORE - SMART (only visible buffers!)
;; ============================================================

;; Custom function to restore only visible buffers
(defun my/desktop-save-only-visible-buffers ()
  "Save desktop but exclude buffers not visible in windows."
  (let* ((visible-buffers (mapcar 'window-buffer (window-list)))
         (visible-buffer-names (mapcar 'buffer-name visible-buffers)))
    ;; Filter desktop-buffer-list to only include visible buffers
    (setq desktop-saved-frameset nil)  ; Don't save frames (faster)
    (let ((desktop-buffers-not-to-save-function
           (lambda (filename bufname mode &rest _)
             (not (member bufname visible-buffer-names)))))
      (desktop-save user-emacs-directory))))

;; Configure desktop mode
(setq desktop-restore-frames nil          ; Don't restore frame geometry (faster!)
      desktop-restore-eager
      
(provide 'init)
;;; init.el ends here
