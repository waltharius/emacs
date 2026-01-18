;;; 05i-denote-utils.el --- Utility functions for Denote  -*- lexical-binding: t; -*-
;;
;; Description: Helper utilities: time/date insertion, search, etc.
;;
;;; Commentary:
;;
;; Small helper functions that don't fit into other modules.
;;
;;; Code:

;; ============================================================
;; UTILITY: Insert current time
;; ============================================================

(defun insert-current-time ()
  "Insert current time in HH:MM format."
  (interactive)
  (insert (format-time-string "%H:%M")))

;; ============================================================
;; UTILITY: Insert current date
;; ============================================================

(defun insert-current-date ()
  "Insert current date in DD-MM-YYYY format."
  (interactive)
  (insert (format-time-string "%d-%m-%Y")))

(provide '05i-denote-utils)
;;; 05i-denote-utils.el ends here
