;;; 06-capture.el --- Org-capture for fleeting notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick capture system for fleeting thoughts and journal ideas
;; Two capture files:
;; - ~/notes/fleeting.org - General fleeting thoughts
;; - ~/notes/journal/captures.org - Ideas from journal to develop later

;;; Code:

;; ============================================================
;; HELPER: Store original buffer info before capture
;; ============================================================

(defvar my/capture-origin-title nil
  "Store the title of the buffer where capture was initiated.")

(defun my/capture-store-origin-title ()
  "Store the title of current buffer before entering capture.
   This runs BEFORE the capture buffer is created."
  (setq my/capture-origin-title
        (condition-case nil
            (or 
             ;; Try to get #+title:
             (when (and (buffer-file-name)
                        (eq major-mode 'org-mode))
               (cadar (org-collect-keywords '("title"))))
             ;; Fallback to filename
             (when (buffer-file-name)
               (file-name-base (buffer-file-name)))
             ;; Last resort: buffer name
             (buffer-name)
             ;; Absolute fallback
             "Untitled")
          ;; If anything fails, return safe default
          (error "Untitled"))))

;; Hook to store title before capture starts
(add-hook 'org-capture-mode-hook 'my/capture-store-origin-title)

(defun my/get-capture-origin-title ()
  "Get the stored origin title for capture template."
  (or my/capture-origin-title "Untitled"))

;; ============================================================
;; ORG-CAPTURE: Configuration
;; ============================================================

(use-package org-capture
  :ensure nil
  :config
  ;; Create capture files if they don't exist
  (unless (file-exists-p my-fleeting-file)
    (with-temp-file my-fleeting-file
      (insert "#+title: Fleeting Notes\n")
      (insert "#+filetags: :fleeting:\n\n")
      (insert "* Inbox\n\n")))
  
  (unless (file-exists-p my-journal-captures)
    (with-temp-file my-journal-captures
      (insert "#+title: Journal Captures\n")
      (insert "#+filetags: :journal:captures:\n\n")))
  
  ;; Capture templates
  (setq org-capture-templates
        '(("f" "Fleeting Note" entry
           (file+headline my-fleeting-file "Inbox")
           "* %?\nCaptured: %U\n"
           :empty-lines 1
           :prepend nil)
          
          ("j" "Journal Capture" entry
           (file+headline my-journal-captures "Ideas from Journal")
           "* %(my/get-capture-origin-title)\n:PROPERTIES:\n:SOURCE: [[%F][%(my/get-capture-origin-title)]]\n:CAPTURED: %U\n:END:\n\n%?"
           :empty-lines 1
           :prepend nil))))

;; ============================================================
;; SMART JOURNAL CAPTURE OPENING
;; ============================================================

(defun my/open-journal-captures ()
  "Open journal captures file.
  - Goes to end of file
  - Adds today's date heading if not present
  - Positions cursor ONE line below date heading (not two!)"
  (interactive)
  (find-file my-journal-captures)
  
  ;; Go to end of file
  (goto-char (point-max))
  
  ;; Get today's date in format: * 2026-02-04 (level 1 heading)
  (let* ((today-date (format-time-string "%Y-%m-%d"))
         (date-heading (concat "* " today-date)))
    
    ;; Search for today's date heading in the file
    (goto-char (point-min))
    (if (search-forward date-heading nil t)
        ;; Date exists - go to end of that section
        (progn
          (org-end-of-subtree)
          (newline)  ; Just ONE newline
          (message "Positioned below existing date: %s" today-date))
      
      ;; Date doesn't exist - add it at the end
      (goto-char (point-max))
      (unless (bolp) (newline 2))  ; Two newlines to separate from previous content
      (insert date-heading "\n")   ; Date heading with ONE newline after it
      (message "Added new date heading: %s" today-date)))
  
  ;; Final positioning - cursor ready to write (already on the line after date)
  (unless (looking-at-p "^$")
    (newline)))

;; ============================================================
;; CAPTURE KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c") 'org-capture)

;; Quick access to capture files
(defun my/open-fleeting-notes ()
  "Open fleeting notes file."
  (interactive)
  (find-file my-fleeting-file)
  (goto-char (point-max)))  ; Also go to end for consistency

(global-set-key (kbd "C-c n f") 'my/open-fleeting-notes)
(global-set-key (kbd "C-c n c") 'my/open-journal-captures)

;; ============================================================
;; WORKFLOW EXPLANATION
;; ============================================================
;;
;; TWO DIFFERENT WAYS TO ADD TO CAPTURES.ORG:
;;
;; Method 1: C-c c j (Structured capture FROM journal notes)
;; -------------------------------------------------------
;; Use this when you're IN a journal/note and want to capture
;; an idea for later development.
;;
;; What it does:
;; - Stores the current note's title
;; - Opens capture dialog
;; - Automatically creates link to current note
;; - Uses stored title for BOTH heading AND link
;; - Adds timestamp
;; - Saves under "Ideas from Journal" heading
;; - Cursor positioned in content area (not heading)
;;
;; Example result:
;; * 2026-02-04 Journal                    ← Auto-filled from source!
;; :PROPERTIES:
;; :SOURCE: [[file:~/notes/journal/2026-02-04-journal.org][2026-02-04 Journal]]
;; :CAPTURED: [2026-02-04 śro 17:05]
;; :END:
;;
;; Your thoughts go here...               ← Cursor starts here
;;
;; Method 2: C-c n c (Quick manual entry by date)
;; -------------------------------------------------------
;; Use this for quick thoughts you want to write down fast,
;; organized by date.
;;
;; What it does:
;; - Opens captures.org
;; - Adds/finds today's date heading (* 2026-02-04)
;; - Positions cursor for immediate typing
;; - No structure, no properties, just write!
;;
;; Example result:
;; * 2026-02-04
;; Quick thought I want to remember.
;; Another thought from later today.
;;
;; WHICH TO USE WHEN?
;; ------------------
;; C-c c j → When reading a note and you get an idea to develop
;; C-c n c → When you just want to jot something down quickly
;;
;; Both methods write to the same file (captures.org) but with
;; different structures. That's OK! Review them later and process.
;;
;; Fleeting Notes (C-c c f):
;; 1. Press C-c c f anywhere to capture a quick thought
;; 2. Type the idea, press C-c C-c to save
;; 3. Later, review ~/notes/fleeting.org
;; 4. Promote good ideas to proper notes in pks/ or docu/

(provide '06-capture)
;;; 06-capture.el ends here
