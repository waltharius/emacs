;;; 27-denote-identifiers.el --- Detect and repair duplicate Denote identifiers -*- lexical-binding: t; -*-

;;; Commentary:
;; The Obsidian migration produced notes whose creation time was
;; unknown, so their identifier is the date plus T000000.  Journal notes
;; without a time in their first heading got the same treatment.  A
;; journal entry and a regular note written on the same day therefore
;; collide - and a Denote identifier is supposed to be unique, because
;; every `denote:' link resolves through it.  The visible symptom is a
;; link that lands on the wrong note, or a journal note linking to
;; itself.
;;
;; This module provides:
;;
;;   `my/denote-check-identifiers'  - report every duplicate group
;;   `my/denote-change-identifier'  - change one note's identifier
;;                                    safely: verify the new one is
;;                                    free, rewrite the front matter,
;;                                    rename the file, and update every
;;                                    `denote:' link pointing at it
;;   `my/denote-fix-duplicates'     - walk the duplicate groups and
;;                                    apply the above, one confirmation
;;                                    per group
;;   `my/denote-find-self-links'    - find notes that link to their own
;;                                    identifier (the damage a collision
;;                                    leaves behind)
;;
;; Two different scopes, and the difference matters:
;;
;;   UNIQUENESS is a property of the three silos (journal, pks, docu).
;;   Only there does a repeated identifier break anything.  A note in
;;   the staging inbox sharing an identifier with a silo note is normal
;;   and expected - both came from a day whose creation time was
;;   unknown - and it is settled when the note is accepted, by moving
;;   the INBOX note, never the filed one.
;;
;;   LINK REWRITING covers everything under `my-notes-dir', inbox
;;   included, because inbox notes link to each other and to silo notes
;;   by identifier.
;;
;; Denote's own file listing is not used for either, since it honours
;; `denote-excluded-directories-regexp', which hides the inbox.

;;; Code:

(require 'subr-x)
(require 'seq)

(defconst my/denote-identifier-regexp "[0-9]\\{8\\}T[0-9]\\{6\\}"
  "Regexp matching a Denote identifier.")

(defcustom my/denote-scan-exclude-regexp "/\\.\\(backups\\|autosaves\\|git\\)/"
  "Paths matching this are skipped when scanning for notes and links."
  :type 'regexp :group 'my)

(defcustom my/denote-silo-directories
  (list my-notes-journal my-notes-pks my-notes-docu)
  "The silos in which an identifier must be unique.
The staging inbox is deliberately absent: a note there may legitimately
share an identifier with a filed note until it is accepted."
  :type '(repeat directory) :group 'my)

;; ============================================================
;; SCANNING
;; ============================================================

(defun my/denote--all-files ()
  "Return every .org file under `my-notes-dir', backups excluded."
  (seq-remove
   (lambda (f) (string-match-p my/denote-scan-exclude-regexp f))
   (directory-files-recursively my-notes-dir "\\.org\\'")))

(defun my/denote--identifier-scope-files ()
  "Return every .org file in the silos where identifiers must be unique.

Named for the scope it describes rather than generically: 05-notes.el
lists the files of a single silo for a different purpose, and the two
carried the same name -- with different arities -- until moving a note
between silos started failing with a wrong-number-of-arguments error."
  (seq-remove
   (lambda (f) (string-match-p my/denote-scan-exclude-regexp f))
   (seq-mapcat (lambda (dir)
                 (when (file-directory-p dir)
                   (directory-files-recursively dir "\\.org\\'")))
               my/denote-silo-directories)))

(defun my/denote--file-identifier (file)
  "Return the identifier in FILE's name, or nil.

Owned here, and also called by 05-notes.el and 25-inbox-review.el:
identifier parsing belongs to the module responsible for identifier
integrity, and one definition is what stops the three from drifting."
  (let ((name (file-name-nondirectory file)))
    (when (string-match (concat "\\`\\(" my/denote-identifier-regexp "\\)")
                        name)
      (match-string 1 name))))

(defun my/denote--identifier-table (&optional files)
  "Return a hash of identifier -> list of files, from FILES."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (or files (my/denote--all-files)) table)
      (when-let* ((id (my/denote--file-identifier file)))
        (puthash id (cons file (gethash id table)) table)))))

(defun my/denote--duplicate-groups (&optional files)
  "Return ((identifier . files) ...) for identifiers used more than once.
FILES defaults to the silo files only - see the scope note above."
  (let (groups)
    (maphash (lambda (id files)
               (when (> (length files) 1)
                 (push (cons id (sort files #'string<)) groups)))
             (my/denote--identifier-table
              (or files (my/denote--identifier-scope-files))))
    (sort groups (lambda (a b) (string< (car a) (car b))))))

(defun my/denote--silo-identifier-table ()
  "Return a hash of identifier -> silo files."
  (my/denote--identifier-table (my/denote--identifier-scope-files)))

(defun my/denote--identifier-free-p (id &optional table)
  "Return non-nil when ID is used by no file in TABLE.
TABLE defaults to the silo table, so freedom means \"free where
uniqueness is required\"."
  (null (gethash id (or table (my/denote--silo-identifier-table)))))

(defun my/denote--next-free-identifier (id &optional table)
  "Return the first free identifier at or after ID, on the SAME DAY.

The date part is never changed: it is the one piece of information the
migration actually knew about the note, and it drives sorting, the
title and the journal correspondence.  Only the time part is bumped,
one second at a time, so the note keeps its position among that day\='s
notes.

Signals an error in the impossible case of a day with 86,400 taken
identifiers, rather than silently moving the note to another date."
  (let* ((table (or table (my/denote--silo-identifier-table)))
         (day (substring id 0 8))
         (seconds (+ (* 3600 (string-to-number (substring id 9 11)))
                     (* 60 (string-to-number (substring id 11 13)))
                     (string-to-number (substring id 13 15))))
         (tried 0)
         candidate)
    (catch 'found
      (while (< tried 86400)
        (setq candidate (format "%sT%02d%02d%02d" day
                                (/ seconds 3600)
                                (% (/ seconds 60) 60)
                                (% seconds 60)))
        (when (my/denote--identifier-free-p candidate table)
          (throw 'found candidate))
        (setq seconds (% (1+ seconds) 86400)
              tried (1+ tried)))
      (user-error "No free identifier left on %s" day))))

;; ============================================================
;; REPORTS
;; ============================================================

;;;###autoload
(defun my/denote-check-identifiers ()
  "Report notes in the silos sharing a Denote identifier.
The staging inbox is not scanned: an inbox note may share an identifier
with a filed note until it is accepted, and that is handled then."
  (interactive)
  (let ((groups (my/denote--duplicate-groups)))
    (if (null groups)
        (message "No duplicate identifiers found")
      (with-current-buffer (get-buffer-create "*Denote Identifier Check*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "%d duplicate identifier(s) in %s\n\n"
                          (length groups)
                          (mapconcat (lambda (d)
                                       (file-name-nondirectory
                                        (directory-file-name d)))
                                     my/denote-silo-directories ", ")))
          (insert "Fix them with M-x my/denote-fix-duplicates, or one at\n"
                  "a time with M-x my/denote-change-identifier in the note.\n\n")
          (dolist (group groups)
            (insert (car group) "\n")
            (dolist (file (cdr group))
              (insert "    " (file-relative-name file my-notes-dir) "\n"))
            (insert "\n")))
        (goto-char (point-min))
        (special-mode)
        (display-buffer (current-buffer)))
      (message "%d duplicate identifier(s)" (length groups)))))

;;;###autoload
(defun my/denote-find-self-links ()
  "Report notes anywhere under `my-notes-dir\=' that link to their own
identifier.
This is what a collision leaves behind: a link meant for another note
resolved to the identifier this file already had."
  (interactive)
  (let (hits)
    (dolist (file (my/denote--all-files))
      (when-let* ((id (my/denote--file-identifier file)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          ;; Skip the #+identifier: line itself.
          (let ((count 0))
            (while (search-forward (concat "denote:" id) nil t)
              (setq count (1+ count)))
            (when (> count 0)
              (push (cons file count) hits))))))
    (if (null hits)
        (message "No self-links found")
      (with-current-buffer (get-buffer-create "*Denote Self Links*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "%d note(s) link to their own identifier:\n\n"
                          (length hits)))
          (dolist (hit (sort hits (lambda (a b) (string< (car a) (car b)))))
            (insert (format "%3d  %s\n" (cdr hit)
                            (file-relative-name (car hit) my-notes-dir)))))
        (goto-char (point-min))
        (special-mode)
        (display-buffer (current-buffer)))
      (message "%d note(s) with self-links" (length hits)))))

;; ============================================================
;; CHANGING AN IDENTIFIER
;; ============================================================

(defun my/denote--replace-in-file (file old new)
  "Replace `denote:OLD' with `denote:NEW' in FILE.
Returns the number of replacements.  Saves the file when it changed;
uses a live buffer when one exists so unsaved edits are not lost."
  (let ((count 0)
        (needle (concat "denote:" old))
        (buffer (find-buffer-visiting file)))
    (if buffer
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-min))
            (while (search-forward needle nil t)
              (replace-match (concat "denote:" new) t t)
              (setq count (1+ count))))
          (when (> count 0) (save-buffer)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (search-forward needle nil t)
          (replace-match (concat "denote:" new) t t)
          (setq count (1+ count)))
        (when (> count 0)
          (write-region (point-min) (point-max) file nil 'quiet))))
    count))

(defun my/denote--set-front-matter-identifier (file new)
  "Set FILE's `#+identifier:' line to NEW."
  (let ((buffer (find-buffer-visiting file)))
    (if buffer
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^#\\+identifier:\\s-*\\(.*\\)$" nil t)
              (replace-match new t t nil 1)))
          (save-buffer))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+identifier:\\s-*\\(.*\\)$" nil t)
          (replace-match new t t nil 1))
        (write-region (point-min) (point-max) file nil 'quiet)))))

(defun my/denote--rename-with-identifier (file new)
  "Rename FILE so its name starts with identifier NEW.  Returns the path."
  (let* ((dir (file-name-directory file))
         (name (file-name-nondirectory file))
         (new-name (replace-regexp-in-string
                    (concat "\\`" my/denote-identifier-regexp) new name t t))
         (target (expand-file-name new-name dir)))
    (when (file-exists-p target)
      (user-error "Target already exists: %s" target))
    (if-let* ((buffer (find-buffer-visiting file)))
        (with-current-buffer buffer
          (set-visited-file-name target nil t)
          (rename-file file target)
          (set-buffer-modified-p nil))
      (rename-file file target))
    target))

(defun my/denote-change-identifier (file new-id)
  "Give FILE the identifier NEW-ID and repoint every link to it.

Interactively, FILE is the current buffer's file (or the file at point
in Dired), and NEW-ID defaults to the first free identifier at or after
the current one - normally the same timestamp bumped by a second.

The order matters: links are rewritten BEFORE the file is renamed, so
an interruption leaves links pointing at a file that still exists under
the old name, which `my/denote-check-identifiers' can still see."
  (interactive
   (let* ((file (or (and (derived-mode-p 'dired-mode) (dired-get-filename nil t))
                    buffer-file-name
                    (user-error "No file here")))
          (old (or (my/denote--file-identifier file)
                   (user-error "Not a Denote file name: %s"
                               (file-name-nondirectory file))))
          (suggestion (my/denote--next-free-identifier old)))
     (list file (read-string (format "New identifier for %s: "
                                     (file-name-nondirectory file))
                             suggestion nil suggestion))))
  (let* ((old (or (my/denote--file-identifier file)
                  (user-error "Not a Denote file name")))
         (table (my/denote--silo-identifier-table)))
    (unless (string-match-p (concat "\\`" my/denote-identifier-regexp "\\'")
                            new-id)
      (user-error "Not a valid identifier: %s" new-id))
    (when (string= old new-id)
      (user-error "That is already the identifier"))
    ;; Uniqueness check comes first - never create a second collision
    ;; while fixing one.
    (unless (my/denote--identifier-free-p new-id table)
      (user-error "Identifier %s is already used in a silo by: %s" new-id
                  (mapconcat (lambda (f) (file-relative-name f my-notes-dir))
                             (gethash new-id table) ", ")))
    (let ((files 0) (links 0))
      (dolist (other (my/denote--all-files))
        ;; The file's own `denote:OLD' links are self-links created by
        ;; an earlier bad resolution; they are rewritten too, and
        ;; `my/denote-find-self-links' will show whether any remain.
        (let ((n (my/denote--replace-in-file other old new-id)))
          (when (> n 0)
            (setq files (1+ files) links (+ links n)))))
      (my/denote--set-front-matter-identifier file new-id)
      (let ((target (my/denote--rename-with-identifier file new-id)))
        (message "%s -> %s (%d link(s) in %d file(s) updated)"
                 old new-id links files)
        target))))

;;;###autoload
(defun my/denote-fix-duplicates ()
  "Walk duplicate identifier groups IN THE SILOS and free up each extra.
The first file in each group keeps the identifier; the rest are offered
a free time on the same day.  Group members sort by path, which is not
a judgement about which note should keep the identifier - the prompt
names both files, so decide per case and answer n to skip.

This is for genuine duplicates inside the silos.  An inbox note that
shares an identifier with a filed note is not one, and is not listed."
  (interactive)
  (let ((groups (my/denote--duplicate-groups))
        (fixed 0))
    (if (null groups)
        (message "No duplicate identifiers found")
      (dolist (group groups)
        (let ((id (car group))
              (keeper (car (cdr group)))
              (others (cdr (cdr group))))
          (dolist (file others)
            (let ((suggestion (my/denote--next-free-identifier id)))
              (when (y-or-n-p
                     (format "%s: keep on %s, move %s to %s? "
                             id
                             (file-relative-name keeper my-notes-dir)
                             (file-relative-name file my-notes-dir)
                             suggestion))
                (my/denote-change-identifier file suggestion)
                (setq fixed (1+ fixed)))))))
      (message "Changed %d identifier(s); re-run M-x my/denote-check-identifiers"
               fixed))))

(provide '27-denote-identifiers)
;;; 27-denote-identifiers.el ends here
