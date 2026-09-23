;;; 46-blog.el --- Publish selected notes as Hugo sites -*- lexical-binding: t; -*-
;;; Commentary:
;; Selected Denote notes become pages of one or more static Hugo sites,
;; built locally and, for sites that have a server, copied there with
;; rsync.  The Org side is ox-hugo (kaushalmodi/ox-hugo), an established
;; Org -> Hugo Markdown exporter; this module adds only what is specific
;; to a Denote notes tree: which notes belong where, how `denote:' links
;; between them are resolved, and what must never leave the machine.
;;
;; SITES AND SECTIONS
;; ------------------
;; `my/blog-sites' lists the sites.  Each site is a Hugo directory with
;; an optional rsync destination and a list of SECTIONS, a section being
;; a directory under content/ (posts, docs).  A note lands in a section
;; when BOTH hold:
;;   - its file name carries the section's Denote keyword;
;;   - it lives in one of the section's silos.
;; One keyword per section, so a note chooses its section by its tag.
;; A note carrying the keywords of two sections of the same site is
;; refused rather than placed in either: which one was meant is not
;; something to guess.  One note may appear on several sites.
;;
;; WHAT THE CONFIGURATION MAY NOT SAY
;; ----------------------------------
;; Checked before every command, so a mistake stops the command instead
;; of publishing something:
;;   - a site with an rsync destination may not take notes from a silo in
;;     `my/blog-private-silos' (journal, inbox): a private silo can only
;;     feed a site that never leaves the laptop;
;;   - a section keyword may not be the name of a silo.  `docu' is both a
;;     silo and a keyword every docu note carries, so as a marker it would
;;     publish the whole silo at once;
;;   - two sections of one site may not share a keyword.
;;
;; WHY THE EXPORT RUNS ON A COPY
;; -----------------------------
;; Each note is exported from a temporary buffer holding a copy of the
;; file, with an `#+export_file_name:' line added on top.  That line is
;; what gives the page a readable URL instead of the Denote file name,
;; and adding it to the note itself would store a derived value in the
;; note -- the thing the hub module refuses to do for the same reason.
;; The copy also keeps the export away from the live buffer: no mode
;; hooks, no live transclusions, no fonts.
;;
;; DENOTE LINKS
;; ------------
;; During an export started from this module, and only then:
;;   - a link to a note published on the SAME site, in any of its
;;     sections, becomes a Hugo `relref' to that page;
;;   - a link to any other note -- private, or on another site -- becomes
;;     its description, as plain text.
;; Both are done by a replacement `:export' function for the `denote'
;; link type, let-bound around the export, so exports started any
;; other way (PDF, ODT, `C-c C-e') are untouched.
;;
;; `my/latex-filter-denote-link' from 16-org-export.el is removed from
;; `org-export-filter-link-functions' for the duration of the export,
;; for two reasons.  As written, it takes its second argument to be the
;; link element, but Org passes filters the backend name there: on Org
;; 9.6 that aborts every export containing a link (reproduced), on Org
;; 9.7 the type test sees nil and the filter does nothing.  And once
;; that is corrected, its fallback branch strips anything shaped like
;; an HTML tag, which a Hugo shortcode -- {{< relref "..." >}} -- is.
;; Removing it by name only needs the symbol, so this module works
;; whether 16-org-export.el is loaded or not.
;;
;; WHAT IS REFUSED
;; ---------------
;; A note that `#+INCLUDE:'s a note not published on the same site is
;; not exported: the included text would be published with it.
;; 20-transclusion.el pairs every `#+transclude:' with such an
;; `#+INCLUDE:', so transcluding a private note is caught here.  Two
;; notes that would get the same URL in one section are also refused,
;; the newer one losing.
;;
;; SECTION DIRECTORIES ARE OWNED BY THIS MODULE
;; --------------------------------------------
;; content/<section>/ holds generated files only.  A full export of a
;; site removes every .md file in each of its sections that no note
;; produced, after a confirmation, which is how removing the keyword
;; unpublishes a note.  Hand-written pages (about, contact) belong
;; elsewhere under content/.  A section removed from `my/blog-sites' is
;; no longer pruned; its directory has to be deleted by hand.
;;
;; MENU (C-c n x b)
;; ----------------
;;   e  export this note          v  preview with `hugo server'
;;   d  dry run of a full export  s  stop a preview
;;   a  export a whole site       p  export, build, upload
;;   o  site folder in Dired      l  last report
;; With more than one site, commands ask which; the last one used is
;; the default.  `e' picks the site from the note's keywords.
;;
;; Requires `hugo' and, for publishing, `rsync' with SSH access to the
;; server; both are checked before any process starts.
;;
;; Docs: ~/.emacs.d/function_helper.org::#blog

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'ox)
(require 'ol)
(require 'ucs-normalize)
(require 'denote)
(require 'transient nil t)

(use-package ox-hugo
  :ensure t
  :defer t)

;; ox-hugo options let-bound below.  The package is loaded lazily, so
;; without these declarations `lexical-binding' would make the bindings
;; lexical and ox-hugo would never see them.
(defvar org-hugo-base-dir)
(defvar org-hugo-section)
(defvar org-hugo-tag-processing-functions)
(declare-function org-hugo-export-to-md "ox-hugo"
                  (&optional async subtreep visible-only))

;; ============================================================
;; SETTINGS
;; ============================================================

(defgroup my/blog nil
  "Publish selected notes as Hugo sites."
  :group 'my/notes)

(defcustom my/blog-sites
  '(("blog"
     :directory "~/projects/blog/"
     :remote nil
     :port 1313
     :sections (("posts" :keyword "blog"   :silos ("pks" "docu"))
                ("docs"  :keyword "pubdoc" :silos ("pks" "docu")))))
  "Hugo sites notes are published to.
Each entry is (NAME . PLIST):
  :directory  root of the Hugo site, the directory holding hugo.toml;
              keep it outside the notes tree -- it is a git repository,
              and git repositories are kept out of Syncthing's reach
  :remote     rsync destination such as \"user@server:/var/www/blog/\"
              (trailing slash matters), or nil for a laptop-only site
  :port       port of `hugo server' for the preview, default 1313
  :sections   list of (SECTION :keyword KEYWORD :silos (SILO ...)),
              SECTION being the directory under content/.
See the Commentary for the rules this is checked against."
  :type 'sexp
  :group 'my/blog)

(defcustom my/blog-default-site "blog"
  "Site offered first when a command asks which site to use."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-private-silos '("journal" "inbox")
  "Silos that may feed only sites without a `:remote'."
  :type '(repeat string)
  :group 'my/blog)

(defcustom my/blog-url-source 'title
  "What the URL of a page is made from.
`title': the title part of the Denote file name, transliterated to
ASCII.  Readable, but renaming the note changes the URL.
`identifier': the Denote identifier.  Stable across renames, opaque."
  :type '(choice (const :tag "Title (readable)" title)
                 (const :tag "Identifier (stable)" identifier))
  :group 'my/blog)

(defcustom my/blog-hugo-program "hugo"
  "Hugo executable."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-rsync-program "rsync"
  "Rsync executable."
  :type 'string
  :group 'my/blog)

(defconst my/blog-report-buffer "*Blog export*"
  "Buffer holding the report of the last export.")

(defconst my/blog-publish-buffer "*Blog publish*"
  "Buffer of the build-and-upload process.")

(defconst my/blog--hugo-config-files
  '("hugo.toml" "hugo.yaml" "hugo.json"
    "config.toml" "config.yaml" "config.json" "config")
  "Names whose presence marks a directory as a Hugo site.")

(defvar my/blog--last-site nil
  "Name of the site the last command worked on, offered next time.")

;; ============================================================
;; SITES: ACCESS AND CHECKS
;; ============================================================

(defun my/blog--site (name)
  "Return the entry of `my/blog-sites' called NAME."
  (or (assoc name my/blog-sites)
      (user-error "No site called %s in `my/blog-sites'" name)))

(defun my/blog--prop (site prop)
  "Return PROP of SITE, an entry of `my/blog-sites'."
  (plist-get (cdr site) prop))

(defun my/blog--directory (site)
  "Return the Hugo root of SITE, as an absolute directory name."
  (file-name-as-directory (expand-file-name (my/blog--prop site :directory))))

(defun my/blog--sections (site)
  "Return the sections of SITE as a list of (NAME . PLIST)."
  (my/blog--prop site :sections))

(defun my/blog--site-keywords (site)
  "Return the section keywords of SITE."
  (mapcar (lambda (sec) (plist-get (cdr sec) :keyword)) (my/blog--sections site)))

(defun my/blog--all-silos ()
  "Return every silo named anywhere in `my/blog-sites'."
  (delete-dups
   (apply #'append
          (mapcar (lambda (site)
                    (apply #'append
                           (mapcar (lambda (sec) (copy-sequence
                                                  (plist-get (cdr sec) :silos)))
                                   (my/blog--sections site))))
                  my/blog-sites))))

(defun my/blog--check-config ()
  "Stop with a readable message when `my/blog-sites' breaks a rule."
  (unless my/blog-sites
    (user-error "No sites in `my/blog-sites'"))
  (let ((silo-names (append (my/blog--all-silos) my/blog-private-silos)))
    (dolist (site my/blog-sites)
      (let ((name (car site))
            (remote (my/blog--prop site :remote))
            (seen '()))
        (unless (stringp (my/blog--prop site :directory))
          (user-error "Site %s has no :directory" name))
        (unless (my/blog--sections site)
          (user-error "Site %s has no :sections" name))
        (dolist (sec (my/blog--sections site))
          (let ((keyword (plist-get (cdr sec) :keyword))
                (silos (plist-get (cdr sec) :silos)))
            (unless (and (stringp keyword) (not (string-empty-p keyword)))
              (user-error "Section %s/%s has no :keyword" name (car sec)))
            (when (member keyword silo-names)
              (user-error "Section %s/%s: keyword `%s' is a silo name and would publish the whole silo"
                          name (car sec) keyword))
            (when (member keyword seen)
              (user-error "Site %s: keyword `%s' used by two sections" name keyword))
            (push keyword seen)
            (unless silos
              (user-error "Section %s/%s has no :silos" name (car sec)))
            (when remote
              (let ((private (seq-intersection silos my/blog-private-silos)))
                (when private
                  (user-error "Site %s has a :remote, so section %s may not take notes from %s"
                              name (car sec) (string-join private ", ")))))))))))

(defun my/blog--read-site ()
  "Return the name of the site to work on, asking when there is a choice."
  (my/blog--check-config)
  (let ((names (mapcar #'car my/blog-sites)))
    (setq my/blog--last-site
          (if (null (cdr names))
              (car names)
            (completing-read "Site: " names nil t nil nil
                             (or my/blog--last-site my/blog-default-site))))))

;; ============================================================
;; WHICH NOTES GO WHERE
;; ============================================================

(defun my/blog--notes-root ()
  "Return the notes tree, falling back when 00-core.el is absent."
  (file-name-as-directory
   (expand-file-name (if (boundp 'my-notes-dir) my-notes-dir "~/notes/"))))

(defun my/blog--silo-of (file)
  "Return the silo FILE is in, or nil when it is not inside one."
  (let ((root (my/blog--notes-root))
        (path (expand-file-name file)))
    (when (string-prefix-p root path)
      (let ((parts (split-string (substring path (length root)) "/" t)))
        ;; A file directly in the root has no silo.
        (when (cdr parts) (car parts))))))

(defun my/blog--excluded-p (file)
  "Non-nil when FILE is under a directory scans must skip.
Uses the rule of 27-denote-identifiers.el when it is loaded, so that
.snapshots and other dot directories are skipped the same way here."
  (string-match-p (if (boundp 'my/denote-scan-exclude-regexp)
                      my/denote-scan-exclude-regexp
                    "/\\.")
                  (substring (expand-file-name file)
                             (length (my/blog--notes-root)))))

(defun my/blog--sections-of (site file)
  "Return the names of the sections of SITE that FILE belongs to.
Nil when FILE is not a note of that site."
  (when (and (stringp file)
             (string-suffix-p ".org" file)
             (file-exists-p file)
             (string-prefix-p (my/blog--notes-root) (expand-file-name file))
             (not (my/blog--excluded-p file)))
    (let ((silo (my/blog--silo-of file))
          (keywords (denote-extract-keywords-from-path file))
          (found '()))
      (dolist (sec (my/blog--sections site))
        (when (and (member silo (plist-get (cdr sec) :silos))
                   (member (plist-get (cdr sec) :keyword) keywords))
          (push (car sec) found)))
      (nreverse found))))

(defun my/blog--sites-of (file)
  "Return the names of the sites FILE would be published on."
  (seq-filter (lambda (name) (my/blog--sections-of (my/blog--site name) file))
              (mapcar #'car my/blog-sites)))

(defun my/blog--candidates (site)
  "Return every note that belongs to at least one section of SITE.
Sorted by file name, which for Denote notes is creation order."
  (let ((root (my/blog--notes-root))
        (silos (delete-dups
                (apply #'append
                       (mapcar (lambda (sec) (copy-sequence
                                              (plist-get (cdr sec) :silos)))
                               (my/blog--sections site)))))
        (files '()))
    (dolist (silo silos)
      (let ((dir (expand-file-name silo root)))
        (when (file-directory-p dir)
          (dolist (file (directory-files-recursively dir "\\.org\\'"))
            (when (my/blog--sections-of site file)
              (push file files))))))
    ;; The order decides which of two colliding URLs is kept: the
    ;; older note's.
    (sort (delete-dups files)
          (lambda (a b) (string< (file-name-nondirectory a)
                                 (file-name-nondirectory b))))))

;; ============================================================
;; URLS
;; ============================================================

(defun my/blog--ascii (string)
  "Return STRING transliterated to lower-case ASCII, hyphen-separated.
Diacritics are decomposed and dropped; `ł', which Unicode does not
decompose, is mapped by hand.  Whatever is still not ASCII goes."
  (let* ((s (replace-regexp-in-string "ł" "l" (downcase string)))
         ;; Decomposition splits "ó" into "o" plus a combining accent;
         ;; the accent is non-ASCII and is dropped before anything else
         ;; is turned into a hyphen, or "żółw" would become "z-o-lw".
         (s (ucs-normalize-NFD-string s))
         (s (replace-regexp-in-string "[[:nonascii:]]+" "" s))
         (s (replace-regexp-in-string "[^a-z0-9-]+" "-" s))
         (s (replace-regexp-in-string "-+" "-" s)))
    (string-trim s "-" "-")))

(defun my/blog--slug (file)
  "Return the URL slug of FILE according to `my/blog-url-source'."
  (let* ((id (or (denote-retrieve-filename-identifier file)
                 (file-name-base file)))
         (title (denote-retrieve-filename-title file))
         (from-title (and title (my/blog--ascii title))))
    (if (and (eq my/blog-url-source 'title)
             from-title
             (not (string-empty-p from-title)))
        from-title
      (downcase id))))

;; ============================================================
;; WHAT IS REFUSED
;; ============================================================

(defun my/blog--included-files (file)
  "Return the files FILE pulls in with #+INCLUDE, as absolute paths."
  (let ((dir (file-name-directory (expand-file-name file)))
        (found '())
        (case-fold-search t))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*#\\+include:[ \t]*\\(?:\"\\([^\"\n]+\\)\"\\|\\([^ \t\n]+\\)\\)"
              nil t)
        (let* ((target (or (match-string 1) (match-string 2)))
               ;; Drop the search part: "file.org::#heading".
               (path (car (split-string target "::"))))
          (push (expand-file-name path dir) found))))
    (nreverse found)))

(defun my/blog--foreign-includes (site file)
  "Return the files FILE includes that are not notes of SITE."
  (seq-remove (lambda (f) (my/blog--sections-of site f))
              (my/blog--included-files file)))

;; ============================================================
;; PLAN
;; ============================================================

(defun my/blog--section-dir (site section)
  "Return content/SECTION/ of SITE."
  (file-name-as-directory
   (expand-file-name (concat "content/" section) (my/blog--directory site))))

(defun my/blog--plan (site)
  "Work out what a full export of SITE would do, writing nothing.
Returns a plist:
  :ready   list of (FILE SECTION SLUG) to export
  :refused list of (FILE REASON) that will not be exported
  :stale   .md files in the section directories no note produces
  :index   identifier -> (SECTION . SLUG) of the notes in :ready"
  (let ((taken (make-hash-table :test #'equal))
        (index (make-hash-table :test #'equal))
        (ready '())
        (refused '()))
    (dolist (file (my/blog--candidates site))
      (let* ((sections (my/blog--sections-of site file))
             (section (car sections))
             (slug (my/blog--slug file))
             (key (concat section "/" slug))
             (foreign (my/blog--foreign-includes site file)))
        (cond
         ((cdr sections)
          (push (list file (format "keywords of several sections: %s"
                                   (string-join sections ", ")))
                refused))
         (foreign
          (push (list file (format "includes a note not on this site: %s"
                                   (mapconcat #'abbreviate-file-name
                                              foreign ", ")))
                refused))
         ((gethash key taken)
          (push (list file (format "URL /%s/ already taken by %s" key
                                   (file-name-nondirectory (gethash key taken))))
                refused))
         (t
          (puthash key file taken)
          (push (list file section slug) ready)))))
    (dolist (entry ready)
      (let ((id (denote-retrieve-filename-identifier (nth 0 entry))))
        (when id (puthash id (cons (nth 1 entry) (nth 2 entry)) index))))
    (let ((stale '()))
      (dolist (sec (my/blog--sections site))
        (let* ((dir (my/blog--section-dir site (car sec)))
               (wanted (delq nil (mapcar (lambda (e)
                                           (when (equal (nth 1 e) (car sec))
                                             (concat (nth 2 e) ".md")))
                                         ready))))
          (when (file-directory-p dir)
            (dolist (f (directory-files dir t "\\.md\\'"))
              (unless (member (file-name-nondirectory f) wanted)
                (push f stale))))))
      (list :ready (nreverse ready)
            :refused (nreverse refused)
            :stale (nreverse stale)
            :index index))))

;; ============================================================
;; EXPORT
;; ============================================================

(defun my/blog--link-export-function (index)
  "Return an `:export' function for `denote:' links resolved by INDEX.
INDEX maps identifiers to (SECTION . SLUG).  A link to a note in INDEX
becomes a Hugo relref, keeping a `::#custom-id' anchor; any other link
becomes its description alone, so nothing about a note that is not on
the site leaves the machine except the words the page itself uses for
it.  A format other than `md' gets the description too: the function
is only installed for Hugo exports."
  (lambda (link description format)
    (let* ((parts (split-string link "::"))
           (search (cadr parts))
           (target (gethash (car parts) index))
           (text (or description "")))
      (if (and target (eq format 'md))
          (format "[%s]({{< relref \"/%s/%s%s\" >}})"
                  (if (string-empty-p text) (cdr target) text)
                  (car target) (cdr target)
                  (if (and search (string-prefix-p "#" search)) search ""))
        text))))

(defun my/blog--link-parameters (index)
  "Return `org-link-parameters' with the site's export for `denote'."
  (let* ((params (copy-alist org-link-parameters))
         (denote-params (copy-sequence (cdr (assoc "denote" params)))))
    (cons (cons "denote" (plist-put denote-params :export
                                    (my/blog--link-export-function index)))
          (assoc-delete-all "denote" params))))

(defun my/blog--require-ox-hugo ()
  "Load ox-hugo or stop with a readable error."
  (unless (require 'ox-hugo nil t)
    (user-error "ox-hugo is not installed (M-x package-install RET ox-hugo)")))

(defun my/blog--check-site (site)
  "Stop unless the directory of SITE is a Hugo site."
  (let ((dir (my/blog--directory site)))
    (cond
     ((not (file-directory-p dir))
      (user-error "Site %s not found: %s (see function_helper.org, Blog setup)"
                  (car site) dir))
     ((not (seq-some (lambda (name) (file-exists-p (expand-file-name name dir)))
                     my/blog--hugo-config-files))
      (user-error "No Hugo configuration in %s" dir))
     ;; ox-hugo copies images into static/ and refuses to export a note
     ;; with an image when the directory is missing.  `hugo new site'
     ;; creates it, but git does not keep empty directories, so a fresh
     ;; clone of the site repository lacks it.
     (t (make-directory (expand-file-name "static" dir) t)))))

(defun my/blog--check-program (program)
  "Stop unless PROGRAM is on PATH."
  (unless (executable-find program)
    (user-error "%s not found on PATH" program)))

(defun my/blog--export-file (site file section slug index)
  "Export FILE to SECTION of SITE as SLUG, resolving links through INDEX.
Returns the path of the Markdown file written."
  ;; Before the `let': its bindings read ox-hugo's own defaults.
  (my/blog--require-ox-hugo)
  (let* ((keywords (my/blog--site-keywords site))
         (org-hugo-base-dir (my/blog--directory site))
         (org-hugo-section section)
         ;; The section keywords mark where a note goes, not what it is
         ;; about, so they are not shown as tags.
         (org-hugo-tag-processing-functions
          (append org-hugo-tag-processing-functions
                  (list (lambda (tags _info) (seq-difference tags keywords)))))
         (org-export-filter-link-functions
          (remq 'my/latex-filter-denote-link org-export-filter-link-functions))
         (org-link-parameters (my/blog--link-parameters index)))
    (with-temp-buffer
      (insert (format "#+export_file_name: %s\n" slug))
      (insert-file-contents file)
      ;; Relative links, images and #+INCLUDE paths resolve against the
      ;; note's own directory, as they would in the note's buffer.
      (setq default-directory (file-name-directory (expand-file-name file)))
      ;; Mode hooks set up fonts, visual fill, transclusion and more,
      ;; none of which an export needs.
      (delay-mode-hooks (org-mode))
      (goto-char (point-min))
      (org-hugo-export-to-md))))

(defun my/blog--save-notes ()
  "Save every modified buffer visiting a file in the notes tree.
The export reads files from disk; an unsaved paragraph would otherwise
be missing from the page.  Returns the number of buffers saved."
  (let ((root (my/blog--notes-root))
        (saved 0))
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and buffer-file-name
                   (buffer-modified-p)
                   (string-prefix-p root (expand-file-name buffer-file-name)))
          (save-buffer)
          (setq saved (1+ saved)))))
    saved))

;; ============================================================
;; REPORT
;; ============================================================

(defun my/blog--table (rows)
  "Return ROWS, a list of (A B) string pairs, as Org table lines."
  (mapconcat (lambda (row)
               (format "| %s | %s |"
                       (replace-regexp-in-string "|" "\\\\vert{}" (nth 0 row))
                       (replace-regexp-in-string "|" "\\\\vert{}" (nth 1 row))))
             rows "\n"))

(defun my/blog--report (site write plan done failed removed)
  "Show the report of an export of SITE.
WRITE is nil for a dry run.  PLAN is from `my/blog--plan'; DONE lists
exported (FILE SECTION SLUG); FAILED lists (FILE MESSAGE); REMOVED
lists the stale files deleted, or the symbol `kept' when deletion was
declined."
  (let ((refused (plist-get plan :refused))
        (stale (plist-get plan :stale))
        (name (lambda (f) (file-name-nondirectory f))))
    (with-current-buffer (get-buffer-create my/blog-report-buffer)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+title: Blog export — %s, %s, %s\n\n"
                        (car site)
                        (if write "written" "dry run")
                        (format-time-string "%Y-%m-%d %H:%M"))
                (format "Site: %s%s\n\n"
                        (abbreviate-file-name (my/blog--directory site))
                        (if (my/blog--prop site :remote)
                            (format " -> %s" (my/blog--prop site :remote))
                          " (laptop only)")))
        (let ((pages (if write done (plist-get plan :ready))))
          (insert (format "* %s (%d)\n"
                          (if write "Exported" "Would export") (length pages)))
          (when pages
            (insert (my/blog--table
                     (mapcar (lambda (e)
                               (list (funcall name (nth 0 e))
                                     (format "/%s/%s/" (nth 1 e) (nth 2 e))))
                             pages))
                    "\n")))
        (insert (format "\n* Refused (%d)\n" (length refused)))
        (when refused
          (insert (my/blog--table
                   (mapcar (lambda (r) (list (funcall name (car r)) (cadr r)))
                           refused))
                  "\n"))
        (when failed
          (insert (format "\n* Failed (%d)\n" (length failed))
                  (my/blog--table
                   (mapcar (lambda (r) (list (funcall name (car r)) (cadr r)))
                           failed))
                  "\n"))
        (insert (format "\n* %s (%d)\n"
                        (cond ((not write) "Would remove from the site")
                              ((eq removed 'kept) "Not published any more, kept on request")
                              (t "Removed from the site"))
                        (length stale)))
        (dolist (f stale)
          (insert (format "- %s/%s\n"
                          (file-name-nondirectory
                           (directory-file-name (file-name-directory f)))
                          (funcall name f))))
        (goto-char (point-min))
        (when (fboundp 'org-mode) (delay-mode-hooks (org-mode)))
        (setq buffer-read-only t)))
    (display-buffer my/blog-report-buffer)))

;; ============================================================
;; COMMANDS: EXPORT
;; ============================================================

(defun my/blog--run (site-name write)
  "Export every note of the site SITE-NAME.  With WRITE nil, only report.
Returns non-nil when every planned note was exported."
  (my/blog--check-config)
  (my/blog--require-ox-hugo)
  (let ((site (my/blog--site site-name)))
    (my/blog--check-site site)
    (my/blog--save-notes)
    (let ((plan (my/blog--plan site))
          (done '())
          (failed '())
          (removed nil))
      (when write
        (dolist (entry (plist-get plan :ready))
          (condition-case err
              (progn
                (apply #'my/blog--export-file site
                       (append entry (list (plist-get plan :index))))
                (push entry done))
            (error (push (list (car entry) (error-message-string err)) failed))))
        (setq done (nreverse done)
              failed (nreverse failed))
        (let ((stale (plist-get plan :stale)))
          (setq removed
                (if (and stale
                         (not (yes-or-no-p
                               (format "Remove %d page(s) no longer published from %s? "
                                       (length stale) site-name))))
                    'kept
                  (dolist (f stale) (delete-file f))
                  stale))))
      (my/blog--report site write plan done failed removed)
      (message "%s %s: %d page(s), %d refused%s"
               site-name
               (if write "export" "dry run")
               (length (if write done (plist-get plan :ready)))
               (length (plist-get plan :refused))
               (if failed (format ", %d FAILED" (length failed)) ""))
      (null failed))))

;;;###autoload
(defun my/blog-export-all-dry-run (site-name)
  "Report what a full export of SITE-NAME would write and remove."
  (interactive (list (my/blog--read-site)))
  (my/blog--run site-name nil))

;;;###autoload
(defun my/blog-export-all (site-name)
  "Export every note of SITE-NAME and remove pages no longer published."
  (interactive (list (my/blog--read-site)))
  (my/blog--run site-name t))

;;;###autoload
(defun my/blog-export-current ()
  "Export the note in the current buffer to the site it belongs to.
When the note belongs to several sites, ask which."
  (interactive)
  (my/blog--check-config)
  (let* ((file (buffer-file-name))
         (sites (and file (my/blog--sites-of file))))
    (unless sites
      (user-error "Not on any site: no section keyword (%s) in a matching silo"
                  (string-join (delete-dups
                                (apply #'append
                                       (mapcar #'my/blog--site-keywords
                                               my/blog-sites)))
                               ", ")))
    (my/blog--require-ox-hugo)
    (let* ((site-name (if (cdr sites)
                          (completing-read "Site: " sites nil t)
                        (car sites)))
           (site (my/blog--site site-name)))
      (setq my/blog--last-site site-name)
      (my/blog--check-site site)
      (when (buffer-modified-p) (save-buffer))
      (let* ((plan (my/blog--plan site))
             (entry (assoc file (plist-get plan :ready)))
             (refusal (assoc file (plist-get plan :refused))))
        (cond
         (refusal (user-error "Not exported: %s" (cadr refusal)))
         ((null entry) (user-error "Not exported: note missing from the plan"))
         (t
          (my/blog--export-file site (nth 0 entry) (nth 1 entry) (nth 2 entry)
                                (plist-get plan :index))
          (message "Exported to %s: /%s/%s/"
                   site-name (nth 1 entry) (nth 2 entry))))))))

;;;###autoload
(defun my/blog-show-report ()
  "Show the report of the last export."
  (interactive)
  (if (get-buffer my/blog-report-buffer)
      (display-buffer my/blog-report-buffer)
    (message "No blog export has been run in this session")))

;;;###autoload
(defun my/blog-open-site (site-name)
  "Open the directory of SITE-NAME in Dired."
  (interactive (list (my/blog--read-site)))
  (let ((dir (my/blog--directory (my/blog--site site-name))))
    (if (file-directory-p dir)
        (dired dir)
      (message "Site not found: %s" dir))))

;; ============================================================
;; COMMANDS: PREVIEW AND PUBLISH
;; ============================================================

(defun my/blog--preview-buffer (site-name)
  "Return the name of the preview buffer of SITE-NAME."
  (format "*Blog preview: %s*" site-name))

(defun my/blog--running-previews ()
  "Return the names of the sites whose preview server is running."
  (seq-filter (lambda (name)
                (let ((proc (get-buffer-process (my/blog--preview-buffer name))))
                  (and proc (process-live-p proc))))
              (mapcar #'car my/blog-sites)))

;;;###autoload
(defun my/blog-preview (site-name)
  "Serve SITE-NAME with `hugo server' and open it in the browser.
The server rebuilds on every change, so exporting a note while it runs
is enough to see the result.  Drafts are shown.  Each site uses its own
`:port', so several previews can run at once; `hugo server' listens on
127.0.0.1 only, so a preview is reachable from this machine alone."
  (interactive (list (my/blog--read-site)))
  (let* ((site (my/blog--site site-name))
         (port (or (my/blog--prop site :port) 1313))
         (url (format "http://localhost:%d/" port))
         (buffer (my/blog--preview-buffer site-name))
         (proc (get-buffer-process buffer)))
    (my/blog--check-site site)
    (my/blog--check-program my/blog-hugo-program)
    (if (and proc (process-live-p proc))
        (browse-url url)
      (make-process
       :name (format "blog-preview-%s" site-name)
       :buffer (get-buffer-create buffer)
       :command (list my/blog-hugo-program "server"
                      "--source" (my/blog--directory site)
                      "--port" (number-to-string port)
                      "--buildDrafts" "--navigateToChanged")
       :noquery t)
      ;; The first build takes a moment; opening the page at once shows
      ;; a connection error instead.
      (run-at-time 2 nil #'browse-url url)
      (message "Hugo server for %s starting - output in %s" site-name buffer))))

;;;###autoload
(defun my/blog-preview-stop ()
  "Stop a `hugo server' started by `my/blog-preview'.
With several running, ask which."
  (interactive)
  (let ((running (my/blog--running-previews)))
    (if (null running)
        (message "No Hugo server running")
      (let ((name (if (cdr running)
                      (completing-read "Stop preview of: " running nil t)
                    (car running))))
        (delete-process (get-buffer-process (my/blog--preview-buffer name)))
        (message "Hugo server for %s stopped" name)))))

(defun my/blog--publish-sentinel (proc _event)
  "Report the end of the build-and-upload PROC."
  (when (memq (process-status proc) '(exit signal))
    (if (zerop (process-exit-status proc))
        (message "Published to %s" (process-get proc 'remote))
      (display-buffer my/blog-publish-buffer)
      (message "Publish FAILED (exit %d) - see %s"
               (process-exit-status proc) my/blog-publish-buffer))))

;;;###autoload
(defun my/blog-publish (site-name)
  "Export every note of SITE-NAME, build the site and upload it.
The upload mirrors public/ to the site's `:remote' with rsync --delete,
so the server ends up holding exactly what was built.  A site without
a `:remote' is laptop-only and cannot be published."
  (interactive (list (my/blog--read-site)))
  (let* ((site (my/blog--site site-name))
         (remote (my/blog--prop site :remote)))
    (unless (and (stringp remote) (not (string-empty-p remote)))
      (user-error "Site %s has no :remote - it is laptop-only" site-name))
    (my/blog--check-program my/blog-hugo-program)
    (my/blog--check-program my/blog-rsync-program)
    (unless (my/blog--run site-name t)
      (unless (yes-or-no-p "Some notes failed to export.  Publish anyway? ")
        (user-error "Publish cancelled - see %s" my/blog-report-buffer)))
    (when (yes-or-no-p (format "Build %s and upload to %s? " site-name remote))
      (let* ((dir (my/blog--directory site))
             (public (file-name-as-directory (expand-file-name "public" dir)))
             (command (format "%s --source %s --gc --minify --cleanDestinationDir && %s -az --delete %s %s"
                              (shell-quote-argument my/blog-hugo-program)
                              (shell-quote-argument dir)
                              (shell-quote-argument my/blog-rsync-program)
                              (shell-quote-argument public)
                              (shell-quote-argument remote))))
        (with-current-buffer (get-buffer-create my/blog-publish-buffer)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert command "\n\n")))
        (let ((proc (make-process
                     :name "blog-publish"
                     :buffer my/blog-publish-buffer
                     :command (list shell-file-name shell-command-switch command)
                     :noquery t
                     :sentinel #'my/blog--publish-sentinel)))
          (process-put proc 'remote remote))
        (message "Building and uploading %s..." site-name)))))

;; ============================================================
;; MENU  (C-c n x b)
;; Docs: ~/.emacs.d/function_helper.org::#menu-blog
;; ============================================================

(transient-define-prefix my/blog-menu ()
  "Publish notes as Hugo sites."
  [["Export"
    ("e" "This note"               my/blog-export-current)
    ("d" "Site - dry run"          my/blog-export-all-dry-run)
    ("a" "Whole site"              my/blog-export-all)]
   ["Site"
    ("v" "Preview (hugo server)"   my/blog-preview)
    ("s" "Stop preview"            my/blog-preview-stop)
    ("p" "Publish to server"       my/blog-publish)]
   ["Look"
    ("o" "Site folder"             my/blog-open-site)
    ("l" "Last report"             my/blog-show-report)]
   [("q" "Quit" transient-quit-one)]])

;; Appended rather than declared in 12-transient.el, so that deleting
;; this file removes the entry with it.  Anchored on "Q", the last key
;; 12-transient.el itself declares in the Export menu, for the reason
;; given in 29-writing-export.el: chaining anchors between feature
;; modules drops everything after a missing one.
(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    (my/transient-append 'my/notes-export-menu "Q"
                         '("b" "Blog (Hugo) →" my/blog-menu))))

(provide '46-blog)
;;; 46-blog.el ends here
