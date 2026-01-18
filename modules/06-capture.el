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
;; CAPTURE KEYBINDINGS
;; ============================================================

(global-set-key (kbd "C-c c") 'org-capture)

;; Quick access to capture files
(defun my/open-fleeting-notes ()
  "Open fleeting notes file."
  (interactive)
  (find-file my-fleeting-file))

(defun my/open-journal-captures ()
  "Open journal captures file."
  (interactive)
  (find-file my-journal-captures))

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
;; Journal Captures Workflow:
;; 1. While writing journal, interesting idea emerges
;; 2. Press C-c c j to capture it
;; 3. It asks for source note name (for the link)
;; 4. Saves to ~/notes/journal/captures.org with backlink
;; 5. Later review captures.org and develop ideas
;;

(provide '06-capture)
;;; 06-capture.el ends here
