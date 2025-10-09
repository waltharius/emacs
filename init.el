;;; init.el --- Modular Emacs configuration -*- lexical-binding: t; -*-
;;
;; Author: Marcin
;; Created: 2025-10-03
;; Description: Modular Emacs config with benchmarking
;;
;;; Code:

;; ============================================================
;; PERFORMANCE MONITORING - MUST BE FIRST!
;; ============================================================

(defvar my/emacs-start-time (current-time)
  "Actual startup time (from when init.el loads).")

;; Create logs directory
(let ((logs-dir (expand-file-name "logs/" user-emacs-directory)))
  (unless (file-exists-p logs-dir)
    (make-directory logs-dir t)))

;; Log file path
(defvar my/startup-log-file
  (expand-file-name
   (format "logs/startup-%s.log" (format-time-string "%Y%m%d-%H%M%S"))
   user-emacs-directory)
  "Benchmark log file for this session.")

;; Benchmark data
(defvar my/benchmark-data nil
  "List of (module . time) pairs.")

;; Module loader with benchmark
(defun my/load-module (module-name)
  "Load MODULE-NAME from modules/ directory with timing."
  (let* ((module-file (expand-file-name
                       (concat "modules/" module-name)
                       user-emacs-directory))
         (start-time (current-time)))
    (if (file-exists-p module-file)
        (progn
          (message "[Loading] %s..." module-name)
          (load-file module-file)
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            (push (cons module-name elapsed) my/benchmark-data)
            (message "[✓ %.3fs] %s" elapsed module-name)))
      (warn "Module not found: %s" module-name))))

;; Save benchmark log
(defun my/save-benchmark-log ()
  "Write startup benchmark to log file."
  (let* ((total-time (float-time (time-subtract (current-time) my/emacs-start-time)))
         (official-time (string-to-number (car (split-string (emacs-init-time))))))
    (with-temp-buffer
      (insert "╔═══════════════════════════════════════════════════════════╗\n")
      (insert (format "║  EMACS STARTUP BENCHMARK - %s  ║\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")))
      (insert "╚═══════════════════════════════════════════════════════════╝\n\n")
      
      ;; Times
      (insert (format "Emacs init-time:         %.3fs (official)\n" official-time))
      (insert (format "Actual measured time:    %.3fs\n" total-time))
      (insert (format "Missing time (desktop):  %.3fs (%.0f%%)\n\n"g
		      
                      (- total-time official-time)
                      (* 100 (/ (- total-time official-time) total-time))))
      
      ;; Module breakdown
      (insert "Module load times (sorted by duration):\n")
      (insert "─────────────────────────────────────────────────────────\n")
      (dolist (entry (sort my/benchmark-data (lambda (a b) (> (cdr a) (cdr b)))))
        (insert (format "  %-40s %6.3fs  (%3.0f%%)\n"
                        (car entry)
                        (cdr entry)
                        (* 100 (/ (cdr entry) total-time)))))
      
      (insert "\n")
      (insert (format "Total modules: %d\n" (length my/benchmark-data)))
      (insert (format "Log file: %s\n" my/startup-log-file))
      
      (write-region (point-min) (point-max) my/startup-log-file)
      (message "📊 Benchmark saved: %s" (file-name-nondirectory my/startup-log-file)))))

(add-hook 'after-init-hook 'my/save-benchmark-log)

;; Command to view log
(defun my/view-startup-log ()
  "Open most recent startup log."
  (interactive)
  (let* ((logs-dir (expand-file-name "logs/" user-emacs-directory))
         (logs (directory-files logs-dir t "startup-.*\\.log$"))
         (latest (car (sort logs 'string>))))
    (if latest
        (find-file latest)
      (message "No logs found in %s" logs-dir))))

;; ============================================================
;; PERFORMANCE OPTIMIZATION
;; ============================================================

;; GC optimization for startup
(setq gc-cons-threshold most-positive-fixnum)

(add-hook 'after-init-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))
            (message "GC threshold reset to 16MB")))

;; Load fresh files
(setq load-prefer-newer t)

;; ============================================================
;; USE-PACKAGE STATISTICS - BEFORE 01-packages.el!
;; ============================================================

(setq use-package-compute-statistics t
      use-package-verbose t
      use-package-minimum-reported-time 0.01)  ; Report packages >10ms

;; ============================================================
;; RECENTF
;; ============================================================

(recentf-mode 1)
(setq recentf-max-saved-items 100
      recentf-auto-cleanup 'never
      recentf-exclude '("\\.git/" "COMMIT_EDITMSG" "\\.elc$" "/elpa/"
                        "^/tmp/" "^#.*#$" "^\\.#"))

;; ============================================================
;; DESKTOP OPTIMIZATION - Only visible buffers
;; ============================================================

(setq desktop-restore-frames nil
      desktop-restore-eager 3
      desktop-lazy-verbose nil
      desktop-load-locked-desktop t
      desktop-auto-save-timeout 300)

;; Kill invisible buffers before exit
(defun my/kill-invisible-buffers ()
  "Kill file buffers not visible in any window."
  (interactive)
  (let ((killed 0))
    (dolist (buf (buffer-list))
      (unless (get-buffer-window buf t)
        (when (buffer-file-name buf)
          (kill-buffer buf)
          (setq killed (1+ killed)))))
    (when (called-interactively-p 'interactive)
      (message "Killed %d invisible buffer(s)" killed))
    killed))

(add-hook 'kill-emacs-hook 'my/kill-invisible-buffers)

;; ============================================================
;; FONT-LOCK
;; ============================================================

(setq jit-lock-defer-time 0.05)

;; ============================================================
;; LOAD MODULES
;; ============================================================

(message "╔═══════════════════════════════════════════════════════════╗")
(message "║          Loading Emacs Configuration...                  ║")
(message "╚═══════════════════════════════════════════════════════════╝")

(my/load-module "00-variables.el")
(my/load-module "01-packages.el")
(my/load-module "02-spelling.el")
(my/load-module "03-ui.el")
(my/load-module "04-denote-core.el")
(my/load-module "05-denote-functions.el")
(my/load-module "05a-folgezettel.el")
(my/load-module "07-git.el")
(my/load-module "08-modern-conveniences.el")
(my/load-module "09-themes-gallery.el")
(my/load-module "10-org-formatting.el")
(my/load-module "11-org-journal.el")
(my/load-module "13-project-management.el")
(my/load-module "14-transient-menus.el")
(my/load-module "06-keybindings.el")  ; LAST!

(message "╔═══════════════════════════════════════════════════════════╗")
(message "║   ✨ Configuration loaded! Run M-x my/view-startup-log ✨ ║")
(message "╚═══════════════════════════════════════════════════════════╝")

;; ============================================================
;; CUSTOM FILE
;; ============================================================

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; ============================================================
;; ORG-MODE ENHANCEMENTS
;; ============================================================

(with-eval-after-load 'org
  (add-hook 'kill-emacs-hook 'org-clock-out nil t)
  (setq org-checkbox-hierarchical-statistics nil
        org-export-use-babel nil))

(provide 'init)
;;; init.el ends here

