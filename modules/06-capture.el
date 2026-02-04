;;; 06-capture.el --- Org-capture for fleeting notes -*- lexical-binding: t; -*-
;;; Commentary:
;; Quick capture system for fleeting thoughts and journal ideas
;; Two capture files:
;; - ~/notes/fleeting.org - General fleeting thoughts
;; - ~/notes/journal/captures.org - Ideas from journal to develop later

;;; Code:

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
      (insert "#+filetags: :journal:captures:\n\n")
      (insert "* Ideas from Journal\n\n")))
  
  ;; Capture templates
  (setq org-capture-templates
        '(("f" "Fleeting Note" entry
           (file+headline my-fleeting-file "Inbox")
           "* %?\nCaptured: %U\n"
           :empty-lines 1
           :prepend nil)
          
          ("j" "Journal Capture" entry
           (file+headline my-journal-captures "Ideas from Journal")
           "* %?\n:PROPERTIES:\n:SOURCE: [[%F][%^{Note name}]]\n:CAPTURED: %U\n:END:\n"
           :empty-lines 1
           :prepend nil))))

;; ============================================================
;; SMART JOURNAL CAPTURE OPENING
;; ============================================================

(defun my/open-journal-captures ()
  "Open journal captures file.
  - Goes to end of file
  - Adds today's date heading if not present
  - Positions cursor below date heading ready to write"
  (interactive)
  (find-file my-journal-captures)
  
  ;; Go to end of file
  (goto-char (point-max))
  
  ;; Get today's date in format: ** 2026-02-04 (just numbers, no day name!)
  (let* ((today-date (format-time-string "%Y-%m-%d"))
         (date-heading (concat "** " today-date)))
    
    ;; Search for today's date heading in the file
    (goto-char (point-min))
    (if (search-forward date-heading nil t)
        ;; Date exists - go to end of that section
        (progn
          (org-end-of-subtree)
          (newline 2)
          (message "Positioned below existing date: %s" today-date))
      
      ;; Date doesn't exist - add it at the end
      (goto-char (point-max))
      (unless (bolp) (newline 2))
      (insert date-heading "\n\n")
      (message "Added new date heading: %s" today-date)))
  
  ;; Final positioning - cursor ready to write
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
;; Fleeting Notes Workflow:
;; 1. Press C-c c f anywhere to capture a quick thought
;; 2. Type the idea, press C-c C-c to save
;; 3. Later, review ~/notes/fleeting.org
;; 4. Promote good ideas to proper notes in pks/ or docu/
;;
;; Journal Captures Workflow (ENHANCED!):
;; 1. Press C-c n c to open journal captures
;; 2. Automatically:
;;    - Goes to end of file
;;    - Adds today's date if not present (** 2026-02-04)
;;    - Positions cursor below date heading
;; 3. Start typing immediately!
;; 4. Each day gets its own heading (just date, no day name)
;; 5. Multiple captures per day stack under same date
;;
;; Alternative: Press C-c c j anywhere to capture with dialog

(provide '06-capture)
;;; 06-capture.el ends here
