;;; 14-typing-analytics.el --- Track typing patterns for ergonomic analysis -*- lexical-binding: t; -*-
;;; Commentary:
;; This module tracks:
;; 1. Command frequency (keyfreq) - which Emacs commands you use most
;; 2. Character-level typing patterns - actual keystrokes, speed, and hand/finger usage
;;
;; All data is stored locally:
;; - ~/.emacs.keyfreq (command statistics)
;; - ~/.emacs.d/keys (character-level data)
;;
;; Purpose: Gather data for ergonomic keyboard selection

;;; Code:

;; ============================================================
;; KEYFREQ: Track command frequency
;; ============================================================

(use-package keyfreq
  :ensure t
  :config
  ;; Enable keyfreq tracking
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1)
  
  ;; Optional: Exclude basic movement commands to focus on meaningful operations
  ;; Uncomment these if you want cleaner statistics:
  ;; (setq keyfreq-excluded-commands
  ;;       '(self-insert-command
  ;;         forward-char
  ;;         backward-char
  ;;         previous-line
  ;;         next-line
  ;;         delete-backward-char
  ;;         mouse-set-point))
  
  (message "✓ Keyfreq tracking enabled (~/.emacs.keyfreq)"))

;; Quick access to view statistics
(global-set-key (kbd "C-c a k") 'keyfreq-show)

;; ============================================================
;; CHARACTER-LEVEL TYPING ANALYTICS
;; ============================================================
;; Based on Pavel Panchekha's typing analytics system
;; Tracks: character frequency, digraphs, timing, hand/finger patterns

(defvar keylog-file (expand-file-name "keys" user-emacs-directory)
  "File to store raw keystroke data with timestamps.")

(defvar keylog-buffer-size 1000
  "Number of keystrokes to buffer before writing to disk.")

(defvar keylog-buffer nil
  "Buffer for keystroke data before writing to file.")

(defvar keylog-last-save-time (current-time)
  "Last time the keylog was saved to disk.")

(defvar keylog-autosave-interval 300
  "Seconds between automatic saves (default: 5 minutes).")

(defun keylog-record-keystroke ()
  "Record a single keystroke with microsecond timestamp."
  (when (and (not (minibufferp))
             (eq this-command 'self-insert-command))
    (let* ((char (char-to-string last-command-event))
           (time (current-time))
           (timestamp (+ (* (nth 0 time) 65536.0)
                        (nth 1 time)
                        (/ (nth 2 time) 1000000.0))))
      ;; Add to buffer
      (push (cons timestamp char) keylog-buffer)
      ;; Check if buffer is full
      (when (>= (length keylog-buffer) keylog-buffer-size)
        (keylog-save-buffer)))))

(defun keylog-save-buffer ()
  "Write buffered keystrokes to file."
  (when keylog-buffer
    (with-temp-buffer
      (dolist (entry (reverse keylog-buffer))
        (insert (format "%.6f\t%s\n" (car entry) (cdr entry))))
      (write-region (point-min) (point-max) keylog-file t 'silent))
    (setq keylog-buffer nil
          keylog-last-save-time (current-time))))

(defun keylog-autosave ()
  "Automatically save keylog buffer if enough time has passed."
  (when (and keylog-buffer
             (> (float-time (time-since keylog-last-save-time))
                keylog-autosave-interval))
    (keylog-save-buffer)))

(defun keylog-enable ()
  "Enable keystroke logging."
  (interactive)
  (add-hook 'post-self-insert-hook #'keylog-record-keystroke)
  (run-with-idle-timer 60 t #'keylog-autosave)
  (add-hook 'kill-emacs-hook #'keylog-save-buffer)
  (message "✓ Character-level typing analytics enabled (~/.emacs.d/keys)"))

(defun keylog-disable ()
  "Disable keystroke logging."
  (interactive)
  (remove-hook 'post-self-insert-hook #'keylog-record-keystroke)
  (keylog-save-buffer)
  (message "✗ Character-level typing analytics disabled"))

(defun keylog-status ()
  "Show current keylog statistics."
  (interactive)
  (message "Keylog: %d keystrokes buffered, file size: %s"
           (length keylog-buffer)
           (if (file-exists-p keylog-file)
               (file-size-human-readable (file-attribute-size (file-attributes keylog-file)))
             "0 bytes")))

;; Enable character-level tracking by default
(keylog-enable)

;; Quick access commands
(global-set-key (kbd "C-c a s") 'keylog-status)
(global-set-key (kbd "C-c a t") 'keylog-disable)  ; Temporarily disable
(global-set-key (kbd "C-c a T") 'keylog-enable)   ; Re-enable

;; ============================================================
;; USAGE INSTRUCTIONS
;; ============================================================
;;
;; Active keybindings:
;; - C-c a k : View command frequency statistics (keyfreq-show)
;; - C-c a s : Show current keylog status
;; - C-c a t : Temporarily disable character tracking
;; - C-c a T : Re-enable character tracking
;;
;; Data locations:
;; - ~/.emacs.keyfreq - Command frequency data
;; - ~/.emacs.d/keys - Raw keystroke data with timestamps
;;
;; Recommended collection period: 2-4 weeks for representative data
;;
;; Privacy: All data stays on your laptop. Both files are in .gitignore.

(provide '14-typing-analytics)
;;; 14-typing-analytics.el ends here
