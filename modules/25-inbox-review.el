;;; 25-inbox-review.el --- Review migrated Obsidian notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Review queue for notes migrated from Obsidian into ~/notes/inbox
;; (a staging folder, deliberately NOT a Denote silo).  Modeled on the
;; Readwise review list in 24-readwise.el: a `tabulated-list-mode'
;; buffer in its own tab, a side window for previews, and single-key
;; actions.
;;
;; M-x my/inbox-review opens the list.  Keys:
;;   RET   preview the note in a side window (view-mode, q closes)
;;   e     edit the note
;;   p / d move to the pks / docu silo (also repairs [[wikilinks]]
;;         pointing at this note from the journal silo)
;;   z     promote: move to pks, open, run `my/zettel-adopt'
;;   t     edit tags (denote-rename-file)
;;   k     reject: move to ~/notes/inbox-odrzucone/
;;   /     filter by title/folder/tags, C-/ clears
;;   g     refresh, S/click sorts, q quits
;;
;; In a note buffer (opened from the list or any org buffer):
;;   M-x my/inbox-extract (C-c X in inbox notes) - carve out the
;;   region / subtree / paragraph into a NEW denote note in a chosen
;;   silo, leaving a denote link behind.
;;
;; The inbox stays invisible to Denote until notes are moved out; see
;; `denote-excluded-directories-regexp' below.

;;; Code:

(require 'org)
(require 'denote)
(require 'seq)
(require 'subr-x)

;; ============================================================
;; CONFIG
;; ============================================================

(defcustom my/inbox-directory (expand-file-name "~/notes/inbox/")
  "Staging folder with migrated notes awaiting review."
  :type 'directory :group 'my)

(defcustom my/inbox-reject-directory
  (expand-file-name "~/notes/inbox-odrzucone/")
  "Where rejected notes go.  A trash folder, not deletion - review
mistakes are certain over months of processing; empty it once, at the
end."
  :type 'directory :group 'my)

(defcustom my/inbox-silos
  `(("pks"  . ,(expand-file-name "~/notes/pks/"))
    ("docu" . ,(expand-file-name "~/notes/docu/")))
  "Silos a reviewed note can be accepted into."
  :type '(alist :key-type string :value-type directory) :group 'my)

(defcustom my/inbox-journal-directory (expand-file-name "~/notes/journal/")
  "Journal silo scanned for wikilinks to repair on accept."
  :type 'directory :group 'my)

(defvar my/inbox-tab-name "Inbox"
  "Name of the tab-bar tab holding the review buffer.")

(defvar my/inbox--buffer "*Inbox Review*")

;; Keep the staging area and the trash invisible to Denote: with
;; `denote-directory' set to ~/notes/ every subdirectory is a silo by
;; default, and half-reviewed notes showing up in denote searches
;; would defeat the point of staging.  "inbox" also matches
;; "inbox-odrzucone" as a substring, which is exactly what we want.
(setq denote-excluded-directories-regexp "inbox")

;; ============================================================
;; COLLECTING ENTRIES
;; ============================================================

(defun my/inbox--files ()
  "Return org files awaiting review."
  (when (file-directory-p my/inbox-directory)
    (directory-files my/inbox-directory t "\\.org\\'")))

(defun my/inbox--file-meta (file)
  "Read FILE's front matter into a plist without visiting it."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (cl-flet ((grab (re)
                (goto-char (point-min))
                (when (re-search-forward re nil t)
                  (string-trim (match-string 1)))))
      (let ((ident (or (grab "^#\\+identifier:\\s-*\\([0-9T]+\\)") "")))
        (list :file file
              :title (or (grab "^#\\+title:\\s-*\\(.+\\)$")
                         (file-name-nondirectory file))
              :date (if (>= (length ident) 8)
                        (format "%s-%s-%s" (substring ident 0 4)
                                (substring ident 4 6) (substring ident 6 8))
                      "")
              :tags (or (grab "^#\\+filetags:\\s-*\\(.+\\)$") "")
              :status (or (grab "^:status:\\s-*\\(.+\\)$") "")
              :source (or (grab "^:source_path:\\s-*\\(.+\\)$") ""))))))

(defun my/inbox--collect ()
  "Return metadata plists for every note in the inbox."
  (mapcar #'my/inbox--file-meta (my/inbox--files)))

;; ============================================================
;; LIST UI
;; ============================================================

(defvar-local my/inbox--entries nil
  "Entries backing the current list.")

(defvar my/inbox--filter ""
  "Text currently filtering the list.  Global so it survives refreshes;
shown in the mode line so a narrowed list never looks complete.")

(defvar my/inbox--sort-key '("Date" . nil)
  "Sort column and direction remembered across refreshes.")

(defvar my/inbox--note-window nil
  "Window used for previews.  Global on purpose - see the identical
variable in 24-readwise.el for the reasoning.")

(defun my/inbox--list-entries (entries)
  "Convert ENTRIES into `tabulated-list-entries' form."
  (mapcar
   (lambda (e)
     (list e (vector
              (plist-get e :date)
              (plist-get e :status)
              (plist-get e :tags)
              (file-name-directory (or (plist-get e :source) ""))
              (plist-get e :title))))
   entries))

;; Defined before `define-derived-mode', which creates NAME-map itself
;; when the symbol is still unbound (same trick as in 24-readwise.el).
(defvar my/inbox-review-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my/inbox-preview)
    (define-key map (kbd "e")   #'my/inbox-edit)
    (define-key map (kbd "p")   (lambda () (interactive) (my/inbox-accept "pks")))
    (define-key map (kbd "d")   (lambda () (interactive) (my/inbox-accept "docu")))
    (define-key map (kbd "z")   #'my/inbox-promote-to-zettel)
    (define-key map (kbd "t")   #'my/inbox-edit-tags)
    (define-key map (kbd "k")   #'my/inbox-reject)
    (define-key map (kbd "/")   #'my/inbox-filter)
    (define-key map (kbd "C-/") #'my/inbox-clear-filter)
    (define-key map (kbd "g")   #'my/inbox-review)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `my/inbox-review-mode'.")

(define-derived-mode my/inbox-review-mode tabulated-list-mode "Inbox"
  "Major mode for reviewing migrated notes.
\\{my/inbox-review-mode-map}"
  (setq tabulated-list-format
        (vector (list "Date" 11 t)
                (list "Status" 9 t)
                (list "Tags" 24 t)
                (list "Folder" 30 t)
                (list "Title" 0 t)))
  (setq tabulated-list-sort-key my/inbox--sort-key)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header)
  (hl-line-mode 1))

(defun my/inbox--render ()
  "Redraw the list applying the current filter."
  (let* ((needle (downcase (string-trim my/inbox--filter)))
         (kept (if (string-empty-p needle)
                   my/inbox--entries
                 (seq-filter
                  (lambda (e)
                    (string-match-p
                     (regexp-quote needle)
                     (downcase (concat (plist-get e :title) " "
                                       (plist-get e :tags) " "
                                       (or (plist-get e :source) "")))))
                  my/inbox--entries))))
    (setq tabulated-list-entries (my/inbox--list-entries kept))
    (tabulated-list-print t)
    (setq mode-line-process
          (unless (string-empty-p needle) (format " [/%s]" needle)))
    (force-mode-line-update)
    (length kept)))

;;;###autoload
(defun my/inbox-review ()
  "List migrated notes awaiting review."
  (interactive)
  (let ((entries (my/inbox--collect)))
    (when (fboundp 'my/fixed-tab-goto)
      (my/fixed-tab-goto my/inbox-tab-name))
    (let ((buffer (get-buffer-create my/inbox--buffer)))
      (with-current-buffer buffer
        (when (derived-mode-p 'my/inbox-review-mode)
          (setq my/inbox--sort-key tabulated-list-sort-key))
        (my/inbox-review-mode)
        (setq my/inbox--entries entries)
        (my/inbox--render))
      (switch-to-buffer buffer)
      (message "%d note(s) left to review%s"
               (length entries)
               (if (string-empty-p my/inbox--filter) ""
                 (format ", filtered by \"%s\"" my/inbox--filter))))))

(defun my/inbox-filter (needle)
  "Filter the list by NEEDLE matching title, tags or source folder."
  (interactive "sFilter: ")
  (setq my/inbox--filter needle)
  (my/inbox--render))

(defun my/inbox-clear-filter ()
  "Clear the current filter."
  (interactive)
  (setq my/inbox--filter "")
  (my/inbox--render))

(defun my/inbox--entry ()
  "Entry at point, or an error."
  (or (tabulated-list-get-id) (user-error "No note at point")))

(defun my/inbox-preview ()
  "Show the note at point in a side window, in `view-mode'."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (buffer (find-file-noselect (plist-get entry :file)))
         (list-window (selected-window))
         (window (if (window-live-p my/inbox--note-window)
                     my/inbox--note-window
                   (setq my/inbox--note-window (split-window-right 70)))))
    (set-window-buffer window buffer)
    (with-current-buffer buffer (view-mode 1))
    (select-window window)
    (goto-char (point-min))
    (ignore list-window)))

(defun my/inbox-edit ()
  "Open the note at point for editing."
  (interactive)
  (let ((buffer (find-file-noselect (plist-get (my/inbox--entry) :file))))
    (with-current-buffer buffer (view-mode -1))
    (pop-to-buffer buffer)))

;; ============================================================
;; ACCEPT / REJECT / PROMOTE
;; ============================================================

(defun my/inbox--identifier (file)
  "Denote identifier from FILE's name."
  (when (string-match "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)"
                      (file-name-nondirectory file))
    (match-string 1 (file-name-nondirectory file))))

(defun my/inbox--link-names (entry)
  "Names under which other notes may wikilink to ENTRY: the original
Obsidian file name and the org title."
  (let ((names (list (plist-get entry :title))))
    (when-let* ((src (plist-get entry :source)))
      (unless (string-empty-p src)
        (push (file-name-sans-extension (file-name-nondirectory src))
              names)))
    (seq-uniq (seq-remove #'string-empty-p names))))

(defun my/inbox--fix-journal-links (entry ident)
  "Rewrite [[name]] wikilinks to ENTRY in the journal as denote links.
Returns the number of links rewritten."
  (let ((total 0))
    (dolist (name (my/inbox--link-names entry))
      (let ((needle (concat "[[" name))
            (link-re (concat "\\[\\[" (regexp-quote name)
                             "\\(?:#[^]|]*\\)?\\(?:|\\([^]]*\\)\\)?\\]\\]")))
        (dolist (file (directory-files my/inbox-journal-directory
                                       t "\\.org\\'"))
          ;; Cheap containment check before visiting the file.
          (when (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (search-forward needle nil t))
            (with-current-buffer (find-file-noselect file)
              (save-excursion
                (goto-char (point-min))
                (while (re-search-forward link-re nil t)
                  (replace-match
                   (format "[[denote:%s][%s]]" ident
                           (or (match-string 1) name))
                   t t)
                  (setq total (1+ total))))
              (save-buffer))))))
    total))

(defun my/inbox--move (file dir)
  "Move FILE into DIR, return the new path."
  (make-directory dir t)
  (let ((target (expand-file-name (file-name-nondirectory file) dir)))
    (when (file-exists-p target)
      (user-error "Already exists: %s" target))
    (rename-file file target)
    target))

(defun my/inbox-accept (silo)
  "Move the note at point into SILO and repair journal links to it."
  (interactive (list (completing-read "Silo: " (mapcar #'car my/inbox-silos)
                                      nil t)))
  (let* ((entry (my/inbox--entry))
         (file (plist-get entry :file))
         (dir (cdr (assoc silo my/inbox-silos)))
         (ident (my/inbox--identifier file)))
    (unless dir (user-error "Unknown silo: %s" silo))
    (let ((target (my/inbox--move file dir))
          (fixed (if ident (my/inbox--fix-journal-links entry ident) 0)))
      (message "%s -> %s%s" (plist-get entry :title) silo
               (if (> fixed 0)
                   (format " (%d journal link(s) repaired)" fixed) ""))
      (ignore target))
    (my/inbox-review)))

(defun my/inbox-reject ()
  "Move the note at point to the reject folder."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (file (plist-get entry :file)))
    (when (yes-or-no-p (format "Reject \"%s\"? " (plist-get entry :title)))
      (my/inbox--move file my/inbox-reject-directory)
      (message "Rejected: %s" (plist-get entry :title))
      (my/inbox-review))))

(defun my/inbox-promote-to-zettel ()
  "Move the note at point to pks, open it and adopt it into the ZK.
The :luhmann: property (its number in the old Obsidian tree) is a
placement hint; follow with `my/zettel-reparent' to slot it under an
existing thread."
  (interactive)
  (let* ((entry (my/inbox--entry))
         (file (plist-get entry :file))
         (dir (cdr (assoc "pks" my/inbox-silos)))
         (ident (my/inbox--identifier file))
         (target (my/inbox--move file dir)))
    (when ident (my/inbox--fix-journal-links entry ident))
    (find-file target)
    (if (fboundp 'my/zettel-adopt)
        (call-interactively #'my/zettel-adopt)
      (message "my/zettel-adopt not available - note moved to pks"))))

(defun my/inbox-edit-tags ()
  "Edit the tags of the note at point via `denote-rename-file'."
  (interactive)
  (let ((file (plist-get (my/inbox--entry) :file)))
    (with-current-buffer (find-file-noselect file)
      (call-interactively #'denote-rename-file))
    (my/inbox-review)))

;; ============================================================
;; EXTRACT PART OF A NOTE INTO A NEW NOTE
;; ============================================================

(defun my/inbox--extract-bounds ()
  "Bounds of the text to extract: region, else subtree, else paragraph."
  (cond
   ((use-region-p)
    (cons (region-beginning) (region-end)))
   ((and (derived-mode-p 'org-mode)
         (save-excursion (ignore-errors (org-back-to-heading t))))
    (save-excursion
      (org-back-to-heading t)
      (let ((beg (point)))
        (org-end-of-subtree t t)
        (cons beg (point)))))
   (t (cons (save-excursion (backward-paragraph) (point))
            (save-excursion (forward-paragraph) (point))))))

;;;###autoload
(defun my/inbox-extract ()
  "Extract the region / subtree / paragraph into a new denote note.
Prompts for title, keywords and target silo.  The extracted text is
replaced with a denote link, so the source keeps its context; the new
note records where it came from in :extracted_from:."
  (interactive)
  (let* ((bounds (my/inbox--extract-bounds))
         (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (default-title
          (string-trim
           (replace-regexp-in-string
            "\\`\\*+\\s-*" ""
            (car (split-string (string-trim text) "\n")))))
         (title (read-string
                 (format "Title (%s): " default-title)
                 nil nil default-title))
         (keywords (denote-keywords-prompt))
         (silo (completing-read "Silo: " (mapcar #'car my/inbox-silos)
                                nil t nil nil "pks"))
         (dir (cdr (assoc silo my/inbox-silos)))
         (ident (format-time-string "%Y%m%dT%H%M%S"))
         (slug (denote-sluggify-title title))
         (fname (if keywords
                    (format "%s--%s__%s.org" ident slug
                            (string-join (denote-sluggify-keywords keywords)
                                         "_"))
                  (format "%s--%s.org" ident slug)))
         (target (expand-file-name fname dir))
         (source (file-name-nondirectory (or buffer-file-name
                                             (buffer-name)))))
    (with-temp-file target
      (insert (format "#+title:      %s\n" title)
              (format "#+date:       %s\n"
                      (format-time-string "[%Y-%m-%d %a %H:%M]"))
              (if keywords
                  (format "#+filetags:   :%s:\n"
                          (string-join keywords ":"))
                "")
              (format "#+identifier: %s\n" ident)
              ":PROPERTIES:\n"
              (format ":extracted_from: %s\n" source)
              ":END:\n\n"
              (string-trim text) "\n"))
    ;; Replace the extracted text with a link to the new note.
    (delete-region (car bounds) (cdr bounds))
    (insert (format "[[denote:%s][%s]]\n" ident title))
    (message "Extracted to %s" (file-name-nondirectory target))))

;; Make the extract command handy in inbox notes without claiming a
;; global key.  NOT "C-c x": that is `my/zotero-menu' globally, and a
;; minor-mode map would shadow it inside exactly the buffers where
;; bibliography lookups are likely.  Capital X is unbound repo-wide.
(defvar my/inbox-note-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c X") #'my/inbox-extract)
    map)
  "Keymap for `my/inbox-note-mode'.")

(define-minor-mode my/inbox-note-mode
  "Minor mode active in notes under `my/inbox-directory'."
  :lighter " Inbox")

(defun my/inbox--maybe-enable-note-mode ()
  "Enable `my/inbox-note-mode' for files inside the inbox."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name my/inbox-directory))
    (my/inbox-note-mode 1)))

(add-hook 'find-file-hook #'my/inbox--maybe-enable-note-mode)


;; ============================================================
;; TRANSIENT MENU  (C-c n t i)
;; Docs: ~/.emacs.d/function_helper.org::#menu-inbox
;; ============================================================
;; Appended to the Tools submenu rather than the top level, following
;; the rule stated in function_helper.org: new external integrations
;; belong under `my/notes-tools-menu'.  The `unless' guard makes
;; reloading this file idempotent, as in 24-readwise.el.

(defun my/inbox-open-directory ()
  "Open the inbox folder in Dired."
  (interactive)
  (if (file-directory-p my/inbox-directory)
      (dired my/inbox-directory)
    (user-error "No inbox directory: %s" my/inbox-directory)))

(defun my/inbox-open-reject-directory ()
  "Open the reject folder in Dired."
  (interactive)
  (if (file-directory-p my/inbox-reject-directory)
      (dired my/inbox-reject-directory)
    (user-error "Nothing rejected yet: %s" my/inbox-reject-directory)))

(transient-define-prefix my/inbox-menu ()
  "Review notes migrated from Obsidian."
  [["Review"
    ("r" "Review inbox"        my/inbox-review)]
   ["In a note"
    ("x" "Extract to new note" my/inbox-extract)]
   ["Files"
    ("o" "Open inbox folder"   my/inbox-open-directory)
    ("O" "Open rejects folder" my/inbox-open-reject-directory)]
   [("q" "Quit" transient-quit-one)]])

(unless (ignore-errors (transient-get-suffix 'my/notes-tools-menu "i"))
  (transient-append-suffix 'my/notes-tools-menu "r"
    '("i" "Inbox \u2192" my/inbox-menu)))

(provide '25-inbox-review)
;;; 25-inbox-review.el ends here
