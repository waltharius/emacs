;;; 28-writing-projects.el --- Writing projects: registry, membership, progress -*- lexical-binding: t; -*-
;;; Commentary:
;; A writing project is a directory under `my/writing-projects-directory'
;; containing one hub file named after the directory, plus subdirectories
;; for material that is not a note (mail, for now).
;;
;; The text itself does NOT live here.  Everything written stays in the
;; Denote silos and carries a `#+project:' line naming the projects it
;; belongs to.  The project directory holds the organisational layer only.
;; That split is deliberate: notes are knowledge and outlive the project,
;; while the hub, its task list and its mail are scaffolding that dies with
;; the deadline.  The hub is a window onto the silos, not a container.
;;
;; TWO RELATIONS, TWO MECHANISMS.  A note can belong to a project or merely
;; mention it, and conflating them makes the project list useless:
;;
;;   belongs   -> `#+project: slug' in the note's front matter, plus a link
;;                in the hub's Materials section (the hub is the fast path,
;;                the keyword is repair data)
;;   mentions  -> Denote keyword `slug' in the file name, nothing else
;;
;; A journal entry tagged `licencjat' records that something about the
;; thesis happened that day.  It is not a chapter.  Listing it as project
;; material would be wrong, so mentions are shown separately and can be
;; promoted with one key.
;;
;; PROGRESS is measured against a character target, over the files linked
;; under "Materiały -> Tekst" only.  Source notes and outlines are excluded
;; because they are not the deliverable.  The measurement runs on exported
;; plain text rather than the Org source: a publisher counts the characters
;; the reader gets, and front matter, drawers and citation syntax can be a
;; fifth of an Org file.
;;
;; RELATION TO OTHER MODULES
;; - Requires nothing.  Degrades if `denote' or `pandoc' are absent.
;; - Appends to the menus of 12-transient via `my/transient-append', so a
;;   missing 12-transient leaves the entry out instead of breaking init.
;; - SUPERSEDES the `org-agenda-files' setting in 05-notes.el.  That line
;;   must be deleted; see the Agenda section below for why.
;; - Overrides `org-clock-persist' from 04-denote.el, whose comment claims
;;   clocking is not part of this workflow.  That comment is now false and
;;   should be corrected there.
;;
;; Docs: ~/.emacs.d/function_helper.org::#writing-projects

;;; Code:

(require 'subr-x)
(require 'seq)

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/writing-projects nil
  "Managing long-form writing projects."
  :group 'org)

(defcustom my/writing-projects-directory (expand-file-name "~/projects/")
  "Root directory holding one subdirectory per writing project.

Deliberately outside the notes tree.  Notes are synchronised by
Syncthing; project directories are meant to be independent git
repositories, and a git repository inside a Syncthing folder needs
`.git' excluded on every device to avoid concurrent writes to the
index."
  :type 'directory
  :group 'my/writing-projects)

(defcustom my/writing-project-subdirectories '("email")
  "Subdirectories created inside every new project directory."
  :type '(repeat string)
  :group 'my/writing-projects)

(defcustom my/writing-project-silos
  (list (expand-file-name "~/notes/pks/")
        (expand-file-name "~/notes/docu/")
        (expand-file-name "~/notes/journal/"))
  "Directories scanned when rebuilding project membership from notes.

Only used by the on-demand rebuild command.  Ordinary operation reads
the hub, which is one file, because scanning several thousand notes on
every project visit would make the project unusable."
  :type '(repeat directory)
  :group 'my/writing-projects)

(defcustom my/writing-count-with-pandoc t
  "When non-nil, count characters of exported plain text via pandoc.

Pandoc resolves citations and strips front matter, drawers and Org
markup, so the number matches what a reader would receive.  When nil,
or when pandoc is not installed, a cruder in-Emacs count is used that
merely skips keyword lines, drawers and comments."
  :type 'boolean
  :group 'my/writing-projects)

(defcustom my/writing-clock-idle-minutes 10
  "Minutes of idleness after which Org asks what to do with the time."
  :type 'integer
  :group 'my/writing-projects)

(defcustom my/writing-clock-auto-clockout-seconds 1800
  "Seconds of idleness after which a running clock stops by itself.

Covers falling asleep over the manuscript.  Nil disables it."
  :type '(choice integer (const nil))
  :group 'my/writing-projects)

(defcustom my/writing-use-mutter-idle nil
  "When non-nil, take idle time from GNOME Mutter over D-Bus.

On X11 Org can use `xprintidle' to learn how long the *user* has been
idle.  Under Wayland there is no such program, so Org falls back to
Emacs' own idle time -- which means time spent reading in a browser
while an Emacs frame is focused is counted as work.

Mutter exposes the session idle time on D-Bus.  Verify it works on this
machine before enabling:

  dbus-send --print-reply --dest=org.gnome.Mutter.IdleMonitor \\
    /org/gnome/Mutter/IdleMonitor/Core \\
    org.gnome.Mutter.IdleMonitor.GetIdletime

This is off by default because it has not been tested here."
  :type 'boolean
  :group 'my/writing-projects)

;; Section headings written into every new hub.  Kept in one place so the
;; parser and the template cannot drift apart.
(defconst my/writing--heading-text "Tekst")
(defconst my/writing--heading-sources "Źródła")
(defconst my/writing--heading-mentions "Wzmianki")

;; ============================================================
;; FRONT MATTER
;; ============================================================
;; Deliberately a `#+keyword:' line rather than an Org property.  Org
;; properties live in a drawer under a heading, and Denote notes start with
;; `#+title:' and often have no top-level heading at all, so a file-scope
;; property would need the awkward `#+PROPERTY: PROJECT foo' form.  A plain
;; keyword line matches what Denote already writes, is greppable from a
;; shell, and takes several values separated by spaces.

(defun my/writing--read-keyword (file keyword)
  "Return the value of KEYWORD from FILE front matter, or nil.
Only the head of the file is read: front matter is always at the top and
loading whole notes here would make membership scans needlessly slow."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file nil 0 1200)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^#\\+%s:[ \t]+\\(.+\\)$" (regexp-quote keyword)) nil t)
        (string-trim (match-string 1))))))

(defun my/writing--file-projects (file)
  "Return the list of project slugs FILE declares membership in."
  (when-let ((value (my/writing--read-keyword file "project")))
    (split-string value "[ \t]+" t)))

(defun my/writing--set-file-projects (slugs)
  "Write SLUGS as the `#+project:' line of the current buffer.
Placed after the last front-matter keyword so it joins the existing
block instead of landing in the body."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+project:.*$" nil t)
        (replace-match (concat "#+project: " (string-join slugs " ")) t t)
      ;; Walk past the contiguous run of keyword lines at the top.
      (goto-char (point-min))
      (while (looking-at "^#\\+[a-zA-Z_]+:")
        (forward-line 1))
      (insert "#+project: " (string-join slugs " ") "\n"))))

;; ============================================================
;; PROJECT REGISTRY
;; ============================================================
;; There is no registry file.  The set of projects is whatever directories
;; exist, and a project is valid when it contains a hub named after it.
;; A separate index would be a second source of truth that can disagree
;; with the file system, and repairing that disagreement is work nobody
;; wants to do.

(defun my/writing--slugify (name)
  "Turn NAME into a directory name.
Polish characters are kept: the notes tree already uses them and one
transliteration rule applied inconsistently is worse than none."
  (let ((s (string-trim name)))
    (setq s (replace-regexp-in-string "[/\\:*?\"<>|]" "" s))
    (setq s (replace-regexp-in-string "[ \t]+" "-" s))
    (downcase s)))

(defun my/writing--project-directory (slug)
  "Return the directory of project SLUG."
  (file-name-as-directory
   (expand-file-name slug my/writing-projects-directory)))

(defun my/writing--hub-file (slug)
  "Return the hub file of project SLUG."
  (expand-file-name (concat slug ".org") (my/writing--project-directory slug)))

(defun my/writing-project-slugs ()
  "Return the slugs of all projects that have a hub file."
  (when (file-directory-p my/writing-projects-directory)
    (seq-filter
     (lambda (slug) (file-exists-p (my/writing--hub-file slug)))
     (seq-remove
      (lambda (name) (string-prefix-p "." name))
      (seq-filter
       (lambda (name)
         (file-directory-p (expand-file-name name my/writing-projects-directory)))
       (directory-files my/writing-projects-directory nil nil t))))))

(defun my/writing--read-project (&optional prompt)
  "Prompt for a project slug with completion."
  (let ((slugs (my/writing-project-slugs)))
    (unless slugs
      (user-error "No writing projects yet -- create one with `my/writing-project-new'"))
    (completing-read (or prompt "Project: ") slugs nil t)))

(defun my/writing--current-project ()
  "Return the slug of the project the current buffer belongs to, or nil.
A buffer inside the project directory belongs to it; so does a note
whose front matter names exactly one project."
  (let ((file (buffer-file-name)))
    (when file
      (or (seq-find (lambda (slug)
                      (string-prefix-p (my/writing--project-directory slug)
                                       (expand-file-name file)))
                    (my/writing-project-slugs))
          (let ((declared (my/writing--file-projects file)))
            (when (= (length declared) 1) (car declared)))))))

;; ============================================================
;; CREATING A PROJECT
;; ============================================================

(defun my/writing--hub-template (title slug target-chars target-date)
  "Return the initial contents of a hub file."
  (concat
   "#+title: " title "\n"
   "#+category: " slug "\n"
   "#+project_slug: " slug "\n"
   "#+target_chars: " (number-to-string target-chars) "\n"
   "#+target_date: " target-date "\n"
   "#+startup: overview\n"
   "#+todo: TODO NEXT INPROGRESS WAITING | DONE CANCELLED\n"
   "#+property: Effort_ALL 0:15 0:30 1:00 2:00 4:00 8:00 16:00\n"
   "#+columns: %48ITEM(Zadanie) %TODO %3PRIORITY %8Effort(Est){:} %8CLOCKSUM(Czas)\n"
   "\n"
   "* Zadania\n"
   "\n"
   "* Czas\n"
   "#+BEGIN: clocktable :scope file :maxlevel 3 :link t :compact t\n"
   "#+END:\n"
   "\n"
   "* Materiały\n"
   "** " my/writing--heading-text "\n"
   "Notatki, które składają się na oddawany tekst.  Tylko one liczą się\n"
   "do celu znakowego.\n"
   "\n"
   "** " my/writing--heading-sources "\n"
   "Notatki źródłowe, konspekty, wypisy.  Nie wchodzą do licznika.\n"
   "\n"
   "* " my/writing--heading-mentions "\n"
   "Generowane automatycznie -- ta sekcja jest nadpisywana w całości.\n"
   "\n"
   "* Poczta\n"))

;;;###autoload
(defun my/writing-project-new (title target-chars target-date)
  "Create a new writing project.

TITLE is the human-readable name, TARGET-CHARS the size of the finished
text, TARGET-DATE the day it is due.  Creates the directory, the
subdirectories from `my/writing-project-subdirectories', the hub file,
and initialises a git repository if git is available.

The repository is local and has no remote: it exists so that a bulk
operation gone wrong can be undone across the whole project at once,
which per-file version history cannot do."
  (interactive
   (list (read-string "Project title: ")
         (read-number "Target characters: " 20000)
         (org-read-date nil nil nil "Deadline: ")))
  (let* ((slug (my/writing--slugify title))
         (dir (my/writing--project-directory slug))
         (hub (my/writing--hub-file slug)))
    (when (file-exists-p hub)
      (user-error "Project `%s' already exists" slug))
    (make-directory dir t)
    (dolist (sub my/writing-project-subdirectories)
      (make-directory (expand-file-name sub dir) t))
    (with-temp-file hub
      (insert (my/writing--hub-template title slug target-chars target-date)))
    (if (executable-find "git")
        (let ((default-directory dir))
          (unless (file-directory-p (expand-file-name ".git" dir))
            (call-process "git" nil nil nil "init" "--quiet")))
      (message "git not found -- project created without a repository"))
    (my/writing-projects-update-agenda-files)
    (find-file hub)
    (message "Project `%s' created in %s" slug dir)))

;;;###autoload
(defun my/writing-project-open (slug)
  "Open the hub file of project SLUG."
  (interactive (list (my/writing--read-project "Open project: ")))
  (find-file (my/writing--hub-file slug)))

;;;###autoload
(defun my/writing-project-dired (slug)
  "Open the directory of project SLUG in Dired."
  (interactive (list (my/writing--read-project "Project directory: ")))
  (dired (my/writing--project-directory slug)))

;; ============================================================
;; HUB SECTIONS
;; ============================================================

(defun my/writing--goto-heading (heading)
  "Move point to the start of the body of HEADING, or return nil."
  (goto-char (point-min))
  (when (re-search-forward
         (format "^\\*+ +%s[ \t]*$" (regexp-quote heading)) nil t)
    (forward-line 1)
    (point)))

(defun my/writing--section-bounds (heading)
  "Return (START . END) of the body of HEADING, or nil.
END is the next heading at the same or a shallower level."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\(\\*+\\) +%s[ \t]*$" (regexp-quote heading)) nil t)
      (let* ((level (length (match-string 1)))
             (start (progn (forward-line 1) (point)))
             (end (or (save-excursion
                        (when (re-search-forward
                               (format "^\\*\\{1,%d\\} " level) nil t)
                          (line-beginning-position)))
                      (point-max))))
        (cons start end)))))

(defun my/writing--links-in-section (heading)
  "Return the Denote identifiers linked under HEADING in this buffer."
  (when-let ((bounds (my/writing--section-bounds heading)))
    (save-excursion
      (goto-char (car bounds))
      (let (ids)
        (while (re-search-forward "\\[\\[denote:\\([^]]+\\)\\]" (cdr bounds) t)
          (push (match-string-no-properties 1) ids))
        (nreverse ids)))))

(defun my/writing--id-to-file (id)
  "Resolve Denote identifier ID to a file path, or nil."
  (when (fboundp 'denote-get-path-by-id)
    (ignore-errors (denote-get-path-by-id id))))

;; ============================================================
;; MEMBERSHIP
;; ============================================================

;;;###autoload
(defun my/writing-project-add-note (slug section)
  "Add the note in the current buffer to project SLUG under SECTION.

Writes both halves of the relation: the `#+project:' keyword into the
note, and a Denote link into the hub.  The hub is what gets read during
normal work; the keyword is what allows the hub to be rebuilt if it is
lost."
  (interactive
   (list (my/writing--read-project "Add to project: ")
         (completing-read "Section: "
                          (list my/writing--heading-text
                                my/writing--heading-sources)
                          nil t nil nil my/writing--heading-text)))
  (let ((file (buffer-file-name)))
    (unless file (user-error "This buffer is not visiting a file"))
    (unless (derived-mode-p 'org-mode) (user-error "Not an Org buffer"))
    (let ((id (my/writing--read-keyword file "identifier"))
          (title (or (my/writing--read-keyword file "title")
                     (file-name-base file))))
      (unless id
        (user-error "No `#+identifier:' -- this does not look like a Denote note"))
      ;; Note side.
      (let ((current (my/writing--file-projects file)))
        (unless (member slug current)
          (my/writing--set-file-projects (append current (list slug)))
          (save-buffer)))
      ;; Hub side.
      (let ((hub (my/writing--hub-file slug)))
        (with-current-buffer (find-file-noselect hub)
          (save-excursion
            (unless (my/writing--goto-heading section)
              (user-error "Hub has no `%s' section" section))
            (let ((bounds (my/writing--section-bounds section)))
              (if (member id (my/writing--links-in-section section))
                  (message "Already listed under %s" section)
                (goto-char (cdr bounds))
                (skip-chars-backward " \t\n")
                (insert (format "\n- [[denote:%s][%s]]\n" id title))
                (save-buffer)
                (message "Added to %s / %s" slug section)))))))))

;;;###autoload
(defun my/writing-project-rebuild-materials (slug)
  "Rebuild the hub's Materials sections for SLUG by scanning the silos.

Repair, not routine: this reads the head of every note in
`my/writing-project-silos'.  Existing entries are kept and only missing
ones are appended, under Źródła, because the scan cannot know whether a
note is deliverable text or a source."
  (interactive (list (my/writing--read-project "Rebuild materials of: ")))
  (let ((found '())
        (scanned 0))
    (dolist (silo my/writing-project-silos)
      (when (file-directory-p silo)
        (dolist (file (directory-files-recursively silo "\\.org\\'"))
          (setq scanned (1+ scanned))
          (when (member slug (my/writing--file-projects file))
            (push file found)))))
    (let ((hub (my/writing--hub-file slug))
          (added 0))
      (with-current-buffer (find-file-noselect hub)
        (let ((known (append (my/writing--links-in-section my/writing--heading-text)
                             (my/writing--links-in-section my/writing--heading-sources))))
          (save-excursion
            (dolist (file (nreverse found))
              (let ((id (my/writing--read-keyword file "identifier"))
                    (title (or (my/writing--read-keyword file "title")
                               (file-name-base file))))
                (when (and id (not (member id known)))
                  (let ((bounds (my/writing--section-bounds my/writing--heading-sources)))
                    (goto-char (cdr bounds))
                    (skip-chars-backward " \t\n")
                    (insert (format "\n- [[denote:%s][%s]]\n" id title))
                    (setq added (1+ added)))))))
          (when (> added 0) (save-buffer))))
      (message "Scanned %d notes, %d newly added to %s" scanned added slug))))

;; ============================================================
;; MENTIONS
;; ============================================================
;; Matched on the file name alone.  Denote encodes keywords after `__' in
;; the name, so this needs no file to be opened -- which is what makes it
;; cheap enough to refresh on every visit, unlike the membership scan.

(defun my/writing--mention-files (slug)
  "Return notes whose Denote keywords include SLUG."
  (let (files)
    (dolist (silo my/writing-project-silos)
      (when (file-directory-p silo)
        (dolist (file (directory-files-recursively silo "\\.org\\'"))
          (let ((base (file-name-base file)))
            (when (and (string-match-p "__" base)
                       (member slug (split-string
                                     (cadr (split-string base "__")) "_" t)))
              (push file files))))))
    (sort files #'string>)))

;;;###autoload
(defun my/writing-project-refresh-mentions (slug)
  "Replace the Wzmianki section of SLUG's hub with a fresh listing.

The whole section is overwritten, so nothing may be written there by
hand -- anything worth keeping belongs in Materials."
  (interactive (list (my/writing--read-project "Refresh mentions of: ")))
  (let ((files (my/writing--mention-files slug)))
    (with-current-buffer (find-file-noselect (my/writing--hub-file slug))
      (save-excursion
        (let ((bounds (my/writing--section-bounds my/writing--heading-mentions)))
          (unless bounds (user-error "Hub has no `%s' section"
                                     my/writing--heading-mentions))
          (delete-region (car bounds) (cdr bounds))
          (goto-char (car bounds))
          (insert "Generowane automatycznie -- ta sekcja jest nadpisywana w całości.\n\n")
          (if (null files)
              (insert "Brak wzmianek.\n\n")
            (dolist (file files)
              (let ((id (my/writing--read-keyword file "identifier"))
                    (title (or (my/writing--read-keyword file "title")
                               (file-name-base file))))
                (insert (if id
                            (format "- [[denote:%s][%s]]\n" id title)
                          (format "- [[file:%s][%s]]\n" file title)))))
            (insert "\n"))))
      (save-buffer))
    (message "%d mention(s) of %s" (length files) slug)))

;; ============================================================
;; PROGRESS
;; ============================================================

(defvar my/writing--char-cache (make-hash-table :test #'equal)
  "Cache of character counts, keyed by (FILE . MODIFICATION-TIME).
Counting shells out to pandoc, which is far too slow to repeat for every
file each time the progress line is drawn.")

(defun my/writing--count-chars-crude (file)
  "Count characters of FILE, skipping keyword lines, drawers and comments."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (flush-lines "^#\\+[a-zA-Z_]+:")
    (goto-char (point-min))
    (flush-lines "^[ \t]*#[^+]")
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*:[A-Za-z_]+:[ \t]*$" nil t)
      (let ((start (line-beginning-position)))
        (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
          (delete-region start (line-end-position)))))
    (buffer-size)))

(defun my/writing--count-chars (file)
  "Return the character count of FILE, cached on its modification time."
  (let* ((mtime (file-attribute-modification-time (file-attributes file)))
         (key (cons file mtime))
         (hit (gethash key my/writing--char-cache)))
    (or hit
        (let ((n (if (and my/writing-count-with-pandoc (executable-find "pandoc"))
                     (with-temp-buffer
                       (if (zerop (call-process "pandoc" nil t nil
                                                "-f" "org" "-t" "plain" file))
                           (buffer-size)
                         (my/writing--count-chars-crude file)))
                   (my/writing--count-chars-crude file))))
          (puthash key n my/writing--char-cache)
          n))))

(defun my/writing-project-stats (slug)
  "Return a plist of progress figures for SLUG."
  (with-current-buffer (find-file-noselect (my/writing--hub-file slug))
    (let* ((target (string-to-number
                    (or (my/writing--read-keyword (buffer-file-name) "target_chars")
                        "0")))
           (date (my/writing--read-keyword (buffer-file-name) "target_date"))
           (ids (my/writing--links-in-section my/writing--heading-text))
           (files (delq nil (mapcar #'my/writing--id-to-file ids)))
           (chars (apply #'+ 0 (mapcar #'my/writing--count-chars files)))
           (days (when date
                   (max 0 (- (time-to-days (org-time-string-to-time date))
                             (time-to-days (current-time)))))))
      (list :target target :chars chars :files (length files)
            :date date :days days))))

;;;###autoload
(defun my/writing-project-progress (slug)
  "Report progress of SLUG in the echo area.

Below the target the message says how much to write per day; above it,
how much to cut.  There is no notion of a drafting or editing phase,
because in practice the two alternate from one session to the next and
a flag would spend most of its life set wrongly."
  (interactive (list (or (my/writing--current-project)
                         (my/writing--read-project "Progress of: "))))
  (let* ((s (my/writing-project-stats slug))
         (target (plist-get s :target))
         (chars (plist-get s :chars))
         (days (plist-get s :days))
         (pct (if (> target 0) (round (* 100.0 (/ (float chars) target))) 0))
         (remaining (- target chars)))
    (message
     "%s: %s / %s znaków (%d%%, %d plików) · %s"
     slug chars target pct (plist-get s :files)
     (cond
      ((null days) "brak terminu")
      ((and (> remaining 0) (> days 0))
       (format "%d dni · %d zn./dzień" days (ceiling (/ (float remaining) days))))
      ((> remaining 0) (format "termin dziś lub minął · brakuje %d" remaining))
      (t (format "%d dni · nadwyżka %d do skrócenia" days (- remaining)))))))

;; ============================================================
;; AGENDA
;; ============================================================
;; Only hub files.  05-notes.el points `org-agenda-files' at the three
;; silos plus the capture file, which means every agenda build reads some
;; 3700 notes looking for TODO keywords that are not there -- the silos
;; hold no tasks, and the TODOs in docu/ are documentation examples that
;; should never appear as work.  Delete that setting in 05-notes.el; while
;; it remains, which value wins depends on module load order, which is not
;; something to leave to chance.
;;
;; Personal tasks are not an exception to be carved out here: a project
;; named "Życie" is a project like any other.

(defun my/writing-projects-update-agenda-files ()
  "Set `org-agenda-files' to the hub file of every writing project."
  (interactive)
  (setq org-agenda-files (mapcar #'my/writing--hub-file (my/writing-project-slugs)))
  (when (called-interactively-p 'interactive)
    (message "org-agenda-files: %d project(s)" (length org-agenda-files))))

(with-eval-after-load 'org
  (my/writing-projects-update-agenda-files))

;; ============================================================
;; CLOCK
;; ============================================================
;; Clocking is opt-in per heading: nothing is measured until `C-c C-x C-i'
;; is pressed on a task, so this cannot leak into unrelated Emacs use.
;; What follows only decides what happens to time that was clocked but not
;; worked.
;;
;; `org-clock-persist' is set to nil in 04-denote.el on the grounds that
;; clocking is not part of this workflow.  It now is.  Persistence matters
;; here because a writing session outlives an Emacs session, and because a
;; clock left running through a crash can be resolved on the next start
;; using the Org file's modification time as the end of the work.

(with-eval-after-load 'org-clock
  (setq org-clock-persist 'history)
  (setq org-clock-history-length 20)
  (setq org-clock-out-remove-zero-time-clocks t)
  (setq org-clock-report-include-clocking-task t)
  ;; Round manual corrections to five-minute steps, so that S-<up> on a
  ;; timestamp inside a CLOCK line moves by a useful amount.  Correcting
  ;; by hand is the fallback whenever idle detection is not trustworthy.
  (setq org-time-stamp-rounding-minutes '(0 5))
  (setq org-clock-idle-time my/writing-clock-idle-minutes)
  (org-clock-persistence-insinuate)
  (when my/writing-clock-auto-clockout-seconds
    (setq org-clock-auto-clockout-timer my/writing-clock-auto-clockout-seconds)
    (org-clock-auto-clockout-insinuate)))

;; Idle time under Wayland.  Org knows how to ask macOS and X11 how long
;; the user has been idle; under Wayland it can only ask Emacs, so time
;; spent reading elsewhere with an Emacs frame focused counts as work.
;; Mutter answers the same question over D-Bus.  UNVERIFIED -- see the
;; docstring of `my/writing-use-mutter-idle' for the check to run first.
(defun my/writing--mutter-idle-seconds ()
  "Return session idle time in seconds according to GNOME Mutter."
  (require 'dbus)
  (/ (float (dbus-call-method
             :session "org.gnome.Mutter.IdleMonitor"
             "/org/gnome/Mutter/IdleMonitor/Core"
             "org.gnome.Mutter.IdleMonitor" "GetIdletime"))
     1000.0))

(defun my/writing--user-idle-seconds (&rest _)
  "Idle seconds from Mutter, falling back to Emacs' own idle time."
  (or (ignore-errors (my/writing--mutter-idle-seconds))
      (org-emacs-idle-seconds)))

(when my/writing-use-mutter-idle
  (with-eval-after-load 'org-clock
    (advice-add 'org-user-idle-seconds :override #'my/writing--user-idle-seconds)))

;; ============================================================
;; MENU
;; ============================================================

(transient-define-prefix my/writing-projects-menu ()
  "Writing projects."
  [["Projekt"
    ("n" "Nowy projekt"      my/writing-project-new)
    ("o" "Otwórz hub"        my/writing-project-open)
    ("D" "Katalog (dired)"   my/writing-project-dired)]
   ["Materiały"
    ("a" "Dodaj tę notatkę"  my/writing-project-add-note)
    ("m" "Odśwież wzmianki"  my/writing-project-refresh-mentions)
    ("R" "Przebuduj ze skanu" my/writing-project-rebuild-materials)]
   ["Postęp i czas"
    ("p" "Postęp"            my/writing-project-progress)
    ("i" "Clock in"          org-clock-in)
    ("c" "Clock out"         org-clock-out)
    ("z" "Anuluj zegar"      org-clock-cancel)
    ("g" "Skocz do zegara"   org-clock-goto)]
   ["Agenda"
    ("A" "Agenda"            org-agenda)
    ("U" "Odśwież pliki agendy" my/writing-projects-update-agenda-files)]
   [("q" "Quit" transient-quit-one)]])

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-menu "x"
                       '("p" "Projekty pisarskie →" my/writing-projects-menu)))

(provide '28-writing-projects)
;;; 28-writing-projects.el ends here
