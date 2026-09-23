;;; 46-blog.el --- Publish selected notes as Hugo sites -*- lexical-binding: t; -*-
;;; Commentary:
;; Selected Denote notes become pages of one or more static Hugo sites,
;; built locally and, for sites that have a server, copied there with
;; rsync.  The Org side is ox-hugo (kaushalmodi/ox-hugo), an established
;; Org -> Hugo Markdown exporter; this module adds only what is specific
;; to a Denote notes tree: which notes belong where, how `denote:' links
;; between them are resolved, what must never leave the machine, and
;; exporting only what changed.
;;
;; SITES AND SECTIONS
;; ------------------
;; `my/blog-sites' lists the sites.  Each site is a Hugo directory with
;; an optional rsync destination and a list of SECTIONS, a section being
;; a directory under content/ (posts, docs, journal).  A note lands in a
;; section when BOTH hold:
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
;;     `my/blog-private-silos' (journal, inbox), and may not use a silo
;;     name as a section keyword.  Every note of a silo carries the
;;     silo's keyword (`docu', `journal'), so such a keyword selects the
;;     whole silo -- intended for the laptop-only journal site, fatal
;;     for a published one;
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
;;     sections, becomes a link to that page (see `my/blog-link-style'
;;     for its form);
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
;; WHY PLAIN LINKS AND NOT RELREF BY DEFAULT
;; -----------------------------------------
;; `hugo server' (reproduced with Hugo 0.166.0, with and without
;; --disableFastRender) renders a page wrongly when, in one rebuild, a
;; new page appears and the page linking to it gains a relref to it:
;; the shortcodes come out as raw text and the text between them is
;; cut at wrong offsets.  That is exactly what publishing a note that
;; others already mention produces.  A full `hugo' build of the same
;; files is correct.  Plain links avoid the shortcode altogether, and a
;; missing target becomes a 404 instead of a failed build (relref
;; stops the build on an unknown page, which a note that failed to
;; export would cause).  They rely on Hugo's default permalinks,
;; /<section>/<slug>/, and on the site living at the root of its
;; host.  `relref' remains available through `my/blog-link-style'.
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
;; INCREMENTAL EXPORT
;; ------------------
;; Each site keeps a state file, .blog-state.eld in its root, holding
;; the identifier -> page table of the last run; per note, the includes
;; and linked identifiers read from it with the modification time they
;; were read at; and per exported note, the modification times of the
;; note and its includes at the moment of export.  A run re-reads only
;; notes whose time changed, and exports a note only when
;;   - its page is missing;
;;   - the note or one of its includes changed since its last export;
;;   - a note it links to was published, unpublished or moved since the
;;     last run (the link turns from text into a link or back);
;;   - it failed last time;
;;   - the site's settings changed since the last run (full rebuild).
;; Recorded times are compared for equality, not against the page's
;; own time: a note synced from a device whose clock runs ahead would
;; otherwise look newer than its page on every run.
;; A lost or deleted state file only costs one full export.  `A' in the
;; menu forces a full export by hand.
;;
;; Exports run in the background: one note at a time from an idle
;; timer, so typing is never held up for more than a single note, and a
;; first export of thousands of journal notes proceeds while Emacs
;; stays usable.  In batch mode there is no one to yield to, and the
;; queue runs in a plain loop.
;;
;; SECTION DIRECTORIES ARE OWNED BY THIS MODULE
;; --------------------------------------------
;; content/<section>/ holds generated files only, except files whose
;; name starts with `_' (_index.md sets a section's title).  A run
;; removes every other .md file in each section that no note produced,
;; which is how removing the keyword unpublishes a note.  A run started
;; by hand asks first when the site has a server; a background run never
;; asks: on a laptop-only site it removes the files, on a site with a
;; server it leaves them and says so.  A section removed from
;; `my/blog-sites' is no longer pruned; its directory has to be deleted
;; by hand.
;;
;; AUTOSTART
;; ---------
;; A site with `:autostart t' is kept up to date without being asked:
;; a few seconds after Emacs starts, an incremental export runs and then
;; `hugo server' starts (no browser); after that, saving a note in one
;; of the site's silos schedules another incremental export.  A missing
;; site directory or Hugo only leaves a line in *Messages*.
;;
;; REPORTS
;; -------
;; A run ends with one line in the echo area.  The full report --
;; exported, refused, failed, removed -- stays in the *Blog export*
;; buffer, opened with `l' from the menu and closed with `q'.
;;
;; MENU (C-c n x b)
;; ----------------
;;   e  export this note          v  preview with `hugo server'
;;   d  dry run of a site         s  stop a preview
;;   a  export a site (changes)   p  export, build, upload
;;   A  export a site (all)       o  site folder in Dired
;;                                l  last report
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
                ("docs"  :keyword "pubdoc" :silos ("pks" "docu"))))
    ("journal"
     :directory "~/projects/journal-site/"
     :remote nil
     :port 1314
     :autostart t
     :broken-links mark
     :sections (("journal" :keyword "journal" :silos ("journal"))
                ("posts"   :keyword "blog"    :silos ("pks" "docu"))
                ("docs"    :keyword "pubdoc"  :silos ("pks" "docu")))))
  "Hugo sites notes are published to.
Each entry is (NAME . PLIST):
  :directory     root of the Hugo site, the directory holding hugo.toml;
                 keep it outside the notes tree: a site under git must
                 stay out of Syncthing's reach, and a copy of the
                 journal must not be synced as a second journal
  :remote        rsync destination such as \"user@server:/var/www/blog/\"
                 (trailing slash matters), or nil for a laptop-only site
  :port          port of `hugo server', default 1313
  :autostart     non-nil: export and serve after start-up, re-export
                 when a note of the site is saved
  :broken-links  value of `org-export-with-broken-links' for this site:
                 nil stops the export of a note with a link Org cannot
                 resolve, `mark' writes [BROKEN LINK: ...] in its place
  :sections      list of (SECTION :keyword KEYWORD :silos (SILO ...)),
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

(defcustom my/blog-link-style 'path
  "Form of links between pages of a site.
`path': a plain Markdown link to /<section>/<slug>/.  Rendered the same
by `hugo server' and `hugo'; assumes Hugo's default permalinks and a
site at the root of its host.
`relref': a Hugo relref shortcode.  Resolved and checked by Hugo, but
`hugo server' garbles a page when the page it links to is created in
the same rebuild (see the Commentary)."
  :type '(choice (const :tag "Plain path (default)" path)
                 (const :tag "Hugo relref shortcode" relref))
  :group 'my/blog)

(defcustom my/blog-autostart-delay 5
  "Seconds of idle time after start-up before autostart sites are updated."
  :type 'number
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

(defconst my/blog--state-file ".blog-state.eld"
  "Name of the state file kept in the root of each site.")

(defconst my/blog--state-format 1
  "Version of the state file and of the export rules.
Part of the fingerprint: raising it makes every site export in full
once, which is what a change in how pages are produced requires.")

(defvar my/blog--last-site nil
  "Name of the site the last command worked on, offered next time.")

(defvar my/blog--jobs nil
  "Alist of site name -> plist of the export running for that site.")

(defvar my/blog--save-timers nil
  "Alist of site name -> idle timer of the export scheduled by a save.")

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

(defun my/blog--site-silos (site)
  "Return every silo the sections of SITE take notes from."
  (delete-dups
   (apply #'append (mapcar (lambda (sec) (copy-sequence (plist-get (cdr sec) :silos)))
                           (my/blog--sections site)))))

(defun my/blog--all-silos ()
  "Return every silo named anywhere in `my/blog-sites'."
  (delete-dups (apply #'append (mapcar #'my/blog--site-silos my/blog-sites))))

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
            (when (member keyword seen)
              (user-error "Site %s: keyword `%s' used by two sections" name keyword))
            (push keyword seen)
            (unless silos
              (user-error "Section %s/%s has no :silos" name (car sec)))
            (when remote
              (when (member keyword silo-names)
                (user-error "Site %s has a :remote, so section %s may not use the silo name `%s' as keyword: it would publish the whole silo"
                            name (car sec) keyword))
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

(defun my/blog--require-ox-hugo ()
  "Load ox-hugo or stop with a readable error."
  (unless (require 'ox-hugo nil t)
    (user-error "ox-hugo is not installed (M-x package-install RET ox-hugo)")))

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
        (files '()))
    (dolist (silo (my/blog--site-silos site))
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
;; STATE: WHAT THE LAST RUN SAW
;; ============================================================

(defun my/blog--mtime (file)
  "Return the modification time of FILE as a float, or nil."
  (when-let* ((attrs (file-attributes file)))
    (float-time (file-attribute-modification-time attrs))))

(defun my/blog--state-path (site)
  "Return the path of the state file of SITE."
  (expand-file-name my/blog--state-file (my/blog--directory site)))

(defun my/blog--fingerprint (site)
  "Return what, when changed, requires SITE to be exported in full."
  (list my/blog--state-format
        my/blog-url-source
        my/blog-link-style
        (my/blog--prop site :broken-links)
        (my/blog--sections site)))

(defun my/blog--read-state (site)
  "Return the state plist of SITE, or nil when there is none."
  (let ((path (my/blog--state-path site)))
    (when (file-readable-p path)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents path)
            (let ((state (read (current-buffer))))
              (and (equal (plist-get state :format) my/blog--state-format)
                   state)))
        ;; A damaged state file is treated as a missing one: the next
        ;; run exports everything and writes a new file.
        (error nil)))))

(defun my/blog--write-state (site state)
  "Write STATE, a plist, as the state file of SITE."
  (with-temp-file (my/blog--state-path site)
    (let ((print-length nil) (print-level nil))
      (insert ";; Written by 46-blog.el; safe to delete (costs one full export).\n")
      (prin1 state (current-buffer))
      (insert "\n"))))

(defun my/blog--hash-to-alist (table)
  "Return the entries of hash TABLE as an alist."
  (let ((alist '()))
    (maphash (lambda (k v) (push (cons k v) alist)) table)
    alist))

(defun my/blog--alist-to-hash (alist)
  "Return ALIST as an `equal' hash table."
  (let ((table (make-hash-table :test #'equal :size (max 16 (length alist)))))
    (dolist (cell alist) (puthash (car cell) (cdr cell) table))
    table))

;; ============================================================
;; READING NOTES: INCLUDES AND LINKS
;; ============================================================

(defun my/blog--read-refs (file)
  "Return (INCLUDES LINKS) of FILE.
INCLUDES are the absolute paths FILE pulls in with #+INCLUDE; LINKS
the identifiers of its `denote:' links."
  (let ((dir (file-name-directory (expand-file-name file)))
        (includes '())
        (links '())
        (case-fold-search t))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*#\\+include:[ \t]*\\(?:\"\\([^\"\n]+\\)\"\\|\\([^ \t\n]+\\)\\)"
              nil t)
        (let ((target (or (match-string 1) (match-string 2))))
          ;; Drop the search part: "file.org::#heading".
          (push (expand-file-name (car (split-string target "::")) dir) includes)))
      (goto-char (point-min))
      (while (re-search-forward "\\[\\[denote:\\([^]:]+\\)" nil t)
        (push (match-string-no-properties 1) links)))
    (list (nreverse includes) (delete-dups (nreverse links)))))

(defun my/blog--refs (file cache)
  "Return (INCLUDES LINKS) of FILE, re-reading it only when changed.
CACHE maps files to (MTIME INCLUDES LINKS) and is updated in place."
  (let ((mtime (my/blog--mtime file))
        (hit (gethash file cache)))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let ((refs (my/blog--read-refs file)))
        (puthash file (cons mtime refs) cache)
        refs))))

;; ============================================================
;; PLAN
;; ============================================================

(defun my/blog--section-dir (site section)
  "Return content/SECTION/ of SITE."
  (file-name-as-directory
   (expand-file-name (concat "content/" section) (my/blog--directory site))))

(defun my/blog--page-file (site section slug)
  "Return the Markdown file of SLUG in SECTION of SITE."
  (expand-file-name (concat slug ".md") (my/blog--section-dir site section)))

(defun my/blog--stamp (file includes)
  "Return the modification times of FILE and its INCLUDES, as a list."
  (mapcar #'my/blog--mtime (cons file includes)))

(defun my/blog--changed-ids (old new)
  "Return identifiers whose page differs between hash tables OLD and NEW."
  (let ((changed '()))
    (maphash (lambda (id page) (unless (equal page (gethash id old)) (push id changed)))
             new)
    (maphash (lambda (id _) (unless (gethash id new) (push id changed))) old)
    changed))

(defun my/blog--plan (site &optional full)
  "Work out what an export of SITE would do, writing nothing.
With FULL, every page counts as needing an export.  Returns a plist:
  :ready    list of (FILE SECTION SLUG) on the site
  :todo     the part of :ready that needs exporting
  :refused  list of (FILE REASON) that will not be exported
  :stale    .md files in the section directories no note produces
  :index    identifier -> (SECTION . SLUG) of the notes in :ready
  :cache    file -> (MTIME INCLUDES LINKS), for the state file
  :stamps   file -> times of the note and its includes at last export
  :full     non-nil when every page is exported"
  (let* ((state (my/blog--read-state site))
         (full (or full
                   (null state)
                   (not (equal (plist-get state :fingerprint)
                               (my/blog--fingerprint site)))))
         (cache (my/blog--alist-to-hash (plist-get state :cache)))
         (stamps (my/blog--alist-to-hash (plist-get state :stamps)))
         (old-index (my/blog--alist-to-hash (plist-get state :index)))
         (retry (plist-get state :retry))
         (taken (make-hash-table :test #'equal))
         (index (make-hash-table :test #'equal))
         (candidates (my/blog--candidates site))
         (on-site (make-hash-table :test #'equal))
         (ready '())
         (refused '()))
    (dolist (file candidates) (puthash file t on-site))
    (dolist (file candidates)
      (let* ((sections (my/blog--sections-of site file))
             (section (car sections))
             (slug (my/blog--slug file))
             (key (concat section "/" slug))
             (foreign (seq-remove (lambda (f) (gethash f on-site))
                                  (car (my/blog--refs file cache)))))
        (cond
         ((cdr sections)
          (push (list file (format "keywords of several sections: %s"
                                   (string-join sections ", ")))
                refused))
         (foreign
          (push (list file (format "includes a note not on this site: %s"
                                   (mapconcat #'abbreviate-file-name foreign ", ")))
                refused))
         ((gethash key taken)
          (push (list file (format "URL /%s/ already taken by %s" key
                                   (file-name-nondirectory (gethash key taken))))
                refused))
         (t
          (puthash key file taken)
          (push (list file section slug) ready)))))
    (setq ready (nreverse ready))
    (dolist (entry ready)
      (let ((id (denote-retrieve-filename-identifier (nth 0 entry))))
        (when id (puthash id (cons (nth 1 entry) (nth 2 entry)) index))))
    (let ((changed (my/blog--changed-ids old-index index))
          (todo '())
          (stale '()))
      (dolist (entry ready)
        (let* ((file (nth 0 entry))
               (refs (my/blog--refs file cache)))
          (when (or full
                    (not (file-exists-p
                          (my/blog--page-file site (nth 1 entry) (nth 2 entry))))
                    (member file retry)
                    (not (equal (gethash file stamps)
                                (my/blog--stamp file (nth 0 refs))))
                    (seq-intersection (nth 1 refs) changed))
            (push entry todo))))
      (dolist (sec (my/blog--sections site))
        (let* ((dir (my/blog--section-dir site (car sec)))
               (wanted (delq nil (mapcar (lambda (e)
                                           (when (equal (nth 1 e) (car sec))
                                             (concat (nth 2 e) ".md")))
                                         ready))))
          (when (file-directory-p dir)
            (dolist (f (directory-files dir t "\\.md\\'"))
              (let ((name (file-name-nondirectory f)))
                ;; _index.md and friends are hand-written section pages.
                (unless (or (string-prefix-p "_" name) (member name wanted))
                  (push f stale)))))))
      ;; Forget notes that are no longer candidates, so the cache does
      ;; not grow with every note that was ever published.
      (maphash (lambda (f _) (unless (gethash f on-site) (remhash f cache))) cache)
      (maphash (lambda (f _) (unless (gethash f on-site) (remhash f stamps))) stamps)
      (list :ready ready
            :todo (nreverse todo)
            :refused (nreverse refused)
            :stale (nreverse stale)
            :index index
            :cache cache
            :stamps stamps
            :full full))))

;; ============================================================
;; EXPORT OF ONE NOTE
;; ============================================================

(defun my/blog--link-export-function (index)
  "Return an `:export' function for `denote:' links resolved by INDEX.
INDEX maps identifiers to (SECTION . SLUG).  A link to a note in INDEX
becomes a link in `my/blog-link-style', keeping a `::#custom-id'
anchor; any other link
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
          (let ((label (if (string-empty-p text) (cdr target) text))
                (anchor (if (and search (string-prefix-p "#" search)) search "")))
            (if (eq my/blog-link-style 'relref)
                (format "[%s]({{< relref \"/%s/%s%s\" >}})"
                        label (car target) (cdr target) anchor)
              (format "[%s](/%s/%s/%s)" label (car target) (cdr target) anchor)))
        text))))

(defun my/blog--link-parameters (index)
  "Return `org-link-parameters' with the site's export for `denote'."
  (let* ((params (copy-alist org-link-parameters))
         (denote-params (copy-sequence (cdr (assoc "denote" params)))))
    (cons (cons "denote" (plist-put denote-params :export
                                    (my/blog--link-export-function index)))
          (assoc-delete-all "denote" params))))

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
         (org-export-with-broken-links (my/blog--prop site :broken-links))
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
      ;; ox-hugo reports each file it writes; thousands of such lines
      ;; would bury everything else in *Messages*.
      (let ((inhibit-message t)
            (message-log-max nil))
        (org-hugo-export-to-md)))))

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

(define-minor-mode my/blog-report-mode
  "Read-only report of a blog export; `q' closes its window.
A minor mode, because binding `q' with `local-set-key' would change
`org-mode-map' and so every Org buffer."
  :lighter nil
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "q") #'quit-window)
            map))

(defun my/blog--write-report (site job)
  "Fill the report buffer from JOB, an export of SITE.  Do not show it."
  (let* ((plan (plist-get job :plan))
         (write (plist-get job :write))
         (removed (plist-get job :removed))
         (kept (plist-get job :kept))
         (pages (if write (reverse (plist-get job :done)) (plist-get plan :todo)))
         (failed (reverse (plist-get job :failed)))
         (refused (plist-get plan :refused))
         (name (lambda (f) (file-name-nondirectory f)))
         (short (lambda (f) (format "%s/%s"
                                    (file-name-nondirectory
                                     (directory-file-name (file-name-directory f)))
                                    (file-name-nondirectory f)))))
    (with-current-buffer (get-buffer-create my/blog-report-buffer)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+title: Blog export — %s, %s, %s\n\n"
                        (car site)
                        (cond ((not write) "dry run")
                              ((plist-get plan :full) "full")
                              (t "changes only"))
                        (format-time-string "%Y-%m-%d %H:%M"))
                (format "Site: %s%s\n" (abbreviate-file-name (my/blog--directory site))
                        (if (my/blog--prop site :remote)
                            (format " -> %s" (my/blog--prop site :remote))
                          " (laptop only)"))
                (format "Pages on the site: %d\n\n" (length (plist-get plan :ready))))
        (insert (format "* %s (%d)\n" (if write "Exported" "Would export") (length pages)))
        (when pages
          (insert (my/blog--table
                   (mapcar (lambda (e) (list (funcall name (nth 0 e))
                                             (format "/%s/%s/" (nth 1 e) (nth 2 e))))
                           pages))
                  "\n"))
        (insert (format "\n* Refused (%d)\n" (length refused)))
        (when refused
          (insert (my/blog--table
                   (mapcar (lambda (r) (list (funcall name (car r)) (cadr r))) refused))
                  "\n"))
        (when failed
          (insert (format "\n* Failed (%d)\n" (length failed))
                  (my/blog--table
                   (mapcar (lambda (r) (list (funcall name (car r)) (cadr r))) failed))
                  "\n"))
        (cond
         ((not write)
          (insert (format "\n* Would remove from the site (%d)\n"
                          (length (plist-get plan :stale))))
          (dolist (f (plist-get plan :stale)) (insert "- " (funcall short f) "\n")))
         (t
          (insert (format "\n* Removed from the site (%d)\n" (length removed)))
          (dolist (f removed) (insert "- " (funcall short f) "\n"))
          (when kept
            (insert (format "\n* Not published any more, still on the site (%d)\n"
                            (length kept)))
            (dolist (f kept) (insert "- " (funcall short f) "\n")))))
        (goto-char (point-min))
        (delay-mode-hooks (org-mode))
        (setq buffer-read-only t)
        (my/blog-report-mode 1)))))

(defun my/blog--summary (site job)
  "Return the one-line summary of JOB, an export of SITE."
  (let* ((plan (plist-get job :plan))
         (write (plist-get job :write))
         (refused (length (plist-get plan :refused)))
         (failed (length (plist-get job :failed)))
         (removed (length (plist-get job :removed)))
         (kept (length (plist-get job :kept)))
         (parts (delq nil
                      (list (format "%d %s" (if write
                                                (length (plist-get job :done))
                                              (length (plist-get plan :todo)))
                                    (if write "exported" "to export"))
                            (unless write
                              (format "%d to remove" (length (plist-get plan :stale))))
                            (when (> removed 0) (format "%d removed" removed))
                            (when (> kept 0) (format "%d no longer published, kept" kept))
                            (when (> refused 0) (format "%d refused" refused))
                            (when (> failed 0) (format "%d FAILED" failed))))))
    (format "%s%s: %s%s"
            (car site)
            (if write "" " (dry run)")
            (string-join parts ", ")
            (if (or (> refused 0) (> failed 0) (not write))
                (concat "  — details: "
                        ;; The command has no global key; its menu path
                        ;; is the way to reach it when the menu exists.
                        (if (fboundp 'my/transient-append)
                            "C-c n x b l"
                          "M-x my/blog-show-report"))
              ""))))

;; ============================================================
;; RUNNING AN EXPORT
;; ============================================================

(defun my/blog--schedule (function)
  "Call FUNCTION when Emacs is next idle, shortly.
The time is taken relative to the current idle period, the way the
Elisp manual recommends for chained idle timers; a plain short delay
set from inside an idle timer would wait for the next idle period."
  (run-with-idle-timer (if (current-idle-time)
                           (time-add (current-idle-time) 0.05)
                         0.2)
                       nil function))

(defun my/blog--finish (site job)
  "Complete JOB, an export of SITE: prune, save state, report, call back.
The job is taken off `my/blog--jobs' even when this fails; otherwise
every later request for the site would wait for a run that is over."
  (let* ((plan (plist-get job :plan))
         (stale (plist-get plan :stale))
         (name (car site))
         (ok (null (plist-get job :failed))))
    (unwind-protect
        (my/blog--finish-1 site job plan stale name)
      (setq my/blog--jobs (assoc-delete-all name my/blog--jobs)))
    (when-let* ((callback (plist-get job :on-done)))
      (funcall callback ok))
    (when (plist-get job :again)
      (my/blog--start name (list :write t :quiet t)))))

(defun my/blog--finish-1 (site job plan stale name)
  "Body of `my/blog--finish': prune STALE, save state, report.
SITE, JOB, PLAN and NAME as in the caller."
  (when (plist-get job :write)
    (cond
     ((null stale))
     ((not (my/blog--prop site :remote))
      ;; Laptop-only: nothing leaves the machine, so no reason to ask.
      (dolist (f stale) (delete-file f))
      (setq job (plist-put job :removed stale)))
     ((and (plist-get job :interactive)
           (yes-or-no-p (format "Remove %d page(s) no longer published from %s? "
                                (length stale) name)))
      (dolist (f stale) (delete-file f))
      (setq job (plist-put job :removed stale)))
     (t (setq job (plist-put job :kept stale))))
    (my/blog--write-state
     site
     (list :format my/blog--state-format
           :fingerprint (my/blog--fingerprint site)
           :index (my/blog--hash-to-alist (plist-get plan :index))
           :cache (my/blog--hash-to-alist (plist-get plan :cache))
           :stamps (my/blog--hash-to-alist (plist-get plan :stamps))
           :retry (mapcar #'car (plist-get job :failed)))))
  (my/blog--write-report site job)
  (let ((summary (my/blog--summary site job))
        (quiet (plist-get job :quiet))
        (changed (or (plist-get job :done) (plist-get job :removed)
                     (plist-get job :failed) (plist-get job :kept))))
    ;; A background run that found nothing to do says nothing.
    (unless (and quiet (not changed))
      (message "%s" summary))))

(defun my/blog--step (site job)
  "Export notes of JOB for about 0.1 s.  Return non-nil when done."
  (let* ((deadline (+ (float-time) 0.1))
         (plan (plist-get job :plan))
         (index (plist-get plan :index)))
    (while (and (plist-get job :queue)
                (< (float-time) deadline))
      (let ((entry (car (plist-get job :queue))))
        (plist-put job :queue (cdr (plist-get job :queue)))
        (condition-case err
            (let* ((file (nth 0 entry))
                   ;; Taken before the export: a note edited while it is
                   ;; being exported must count as changed next time.
                   (stamp (my/blog--stamp
                           file (nth 1 (gethash file (plist-get plan :cache))))))
              (my/blog--export-file site file (nth 1 entry) (nth 2 entry) index)
              (puthash file stamp (plist-get plan :stamps))
              (plist-put job :done (cons entry (plist-get job :done))))
          (error
           (plist-put job :failed (cons (list (nth 0 entry) (error-message-string err))
                                        (plist-get job :failed)))))))
    (null (plist-get job :queue))))

(defun my/blog--drive (site job)
  "Run JOB for SITE to the end, yielding to the user between steps."
  (if noninteractive
      (progn
        (while (not (my/blog--step site job)))
        (my/blog--finish site job))
    (let ((tick nil))
      (setq tick
            (lambda ()
              (if (condition-case err
                      (my/blog--step site job)
                    (error (message "Blog export stopped: %s" (error-message-string err))
                           t))
                  (my/blog--finish site job)
                (my/blog--schedule tick))))
      (my/blog--schedule tick))))

(defun my/blog--start (site-name options)
  "Start an export of SITE-NAME.  OPTIONS is a plist:
  :write        nil for a dry run
  :full         export every page, not only the changed ones
  :interactive  started by a command: save notes first, may ask
  :quiet        background run: say nothing when nothing changed
  :on-done      function called with non-nil when nothing failed
While an export of the site runs, a new request is remembered and
served by one more incremental run afterwards."
  (let ((running (assoc site-name my/blog--jobs)))
    (if running
        (progn
          (plist-put (cdr running) :again t)
          (unless (plist-get options :quiet)
            (message "%s: export already running, another will follow" site-name)))
      (my/blog--check-config)
      (my/blog--require-ox-hugo)
      (let ((site (my/blog--site site-name)))
        (my/blog--check-site site)
        (when (plist-get options :interactive) (my/blog--save-notes))
        (let* ((plan (my/blog--plan site (plist-get options :full)))
               (job (append (list :plan plan
                                  :queue (and (plist-get options :write)
                                              (plist-get plan :todo))
                                  :done nil :failed nil)
                            options)))
          (if (not (plist-get options :write))
              (my/blog--finish site job)
            (push (cons site-name job) my/blog--jobs)
            (when (> (length (plist-get job :queue)) 20)
              (message "%s: exporting %d page(s) in the background"
                       site-name (length (plist-get job :queue))))
            (my/blog--drive site job)))))))

;; ============================================================
;; COMMANDS: EXPORT
;; ============================================================

;;;###autoload
(defun my/blog-export-all-dry-run (site-name)
  "Report what an export of SITE-NAME would write and remove."
  (interactive (list (my/blog--read-site)))
  (my/blog--start site-name (list :write nil :interactive t)))

;;;###autoload
(defun my/blog-export-all (site-name)
  "Export the notes of SITE-NAME that changed, remove unpublished pages."
  (interactive (list (my/blog--read-site)))
  (my/blog--start site-name (list :write t :interactive t)))

;;;###autoload
(defun my/blog-export-all-full (site-name)
  "Export every note of SITE-NAME, changed or not."
  (interactive (list (my/blog--read-site)))
  (my/blog--start site-name (list :write t :full t :interactive t)))

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
                                       (mapcar #'my/blog--site-keywords my/blog-sites)))
                               ", ")))
    (my/blog--require-ox-hugo)
    (let* ((site-name (if (cdr sites) (completing-read "Site: " sites nil t) (car sites)))
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
          (message "Exported to %s: /%s/%s/" site-name (nth 1 entry) (nth 2 entry))))))))

;;;###autoload
(defun my/blog-show-report ()
  "Show the report of the last export; `q' closes it."
  (interactive)
  (if (get-buffer my/blog-report-buffer)
      (pop-to-buffer my/blog-report-buffer)
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

(defun my/blog--preview-url (site)
  "Return the address `hugo server' serves SITE on."
  (format "http://localhost:%d/" (or (my/blog--prop site :port) 1313)))

(defun my/blog--serving-p (site-name)
  "Non-nil when the preview server of SITE-NAME is running."
  (let ((proc (get-buffer-process (my/blog--preview-buffer site-name))))
    (and proc (process-live-p proc))))

(defun my/blog--serve (site-name follow)
  "Start `hugo server' for SITE-NAME unless it runs.  Return non-nil if started.
With FOLLOW, the browser is sent to each page that changes, which suits
a preview opened by hand and would be a nuisance for a server that runs
all day."
  (let ((site (my/blog--site site-name)))
    (unless (my/blog--serving-p site-name)
      (make-process
       :name (format "blog-preview-%s" site-name)
       :buffer (get-buffer-create (my/blog--preview-buffer site-name))
       :command (append (list my/blog-hugo-program "server"
                              "--source" (my/blog--directory site)
                              "--port" (number-to-string
                                        (or (my/blog--prop site :port) 1313))
                              "--buildDrafts")
                        (when follow (list "--navigateToChanged")))
       :noquery t)
      t)))

(defun my/blog--running-previews ()
  "Return the names of the sites whose preview server is running."
  (seq-filter #'my/blog--serving-p (mapcar #'car my/blog-sites)))

;;;###autoload
(defun my/blog-preview (site-name)
  "Serve SITE-NAME with `hugo server' and open it in the browser.
The server rebuilds on every change, so exporting a note while it runs
is enough to see the result.  Drafts are shown.  Each site uses its own
`:port', so several previews can run at once; `hugo server' listens on
127.0.0.1 only, so a preview is reachable from this machine alone."
  (interactive (list (my/blog--read-site)))
  (let* ((site (my/blog--site site-name))
         (url (my/blog--preview-url site)))
    (my/blog--check-site site)
    (my/blog--check-program my/blog-hugo-program)
    (if (my/blog--serve site-name t)
        (progn
          ;; The first build takes a moment; opening the page at once
          ;; shows a connection error instead.
          (run-at-time 2 nil #'browse-url url)
          (message "Hugo server for %s starting on %s" site-name url))
      (browse-url url))))

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

(defun my/blog--build-and-upload (site-name)
  "Build SITE-NAME with Hugo and mirror it to its `:remote'."
  (let* ((site (my/blog--site site-name))
         (remote (my/blog--prop site :remote))
         (dir (my/blog--directory site))
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
    (message "Building and uploading %s..." site-name)))

;;;###autoload
(defun my/blog-publish (site-name)
  "Export what changed in SITE-NAME, build the site and upload it.
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
    (my/blog--start
     site-name
     (list :write t :interactive t
           :on-done (lambda (ok)
                      (when (and (or ok (yes-or-no-p "Some notes failed to export.  Publish anyway? "))
                                 (yes-or-no-p (format "Build %s and upload to %s? "
                                                      site-name remote)))
                        (my/blog--build-and-upload site-name)))))))

;; ============================================================
;; AUTOSTART
;; ============================================================

(defun my/blog--autostart-site (site)
  "Export what changed in SITE, then serve it.  Never signal.
Problems -- no site directory, no Hugo -- go to *Messages* only: a
machine without the site should start as quietly as one with it."
  (let ((name (car site)))
    (condition-case err
        (progn
          (my/blog--check-site site)
          (my/blog--check-program my/blog-hugo-program)
          (my/blog--start name
                          (list :write t :quiet t
                                :on-done (lambda (_ok) (my/blog--serve name nil)))))
      (error
       (let ((inhibit-message t))
         (message "Blog autostart, %s: %s" name (error-message-string err)))))))

(defun my/blog--autostart ()
  "Bring every site with `:autostart' up to date and serve it."
  (condition-case err
      (progn
        (my/blog--check-config)
        (dolist (site my/blog-sites)
          (when (my/blog--prop site :autostart)
            (my/blog--autostart-site site))))
    (error (message "Blog autostart: %s" (error-message-string err)))))

(defun my/blog--after-save ()
  "Schedule an export of each autostart site the saved note may concern.
A note concerns a site when it lives in one of the site's silos, with
or without the keyword: a note whose keyword was just removed has to
be taken off the site, too."
  (when-let* ((file buffer-file-name)
              (silo (my/blog--silo-of file)))
    (when (string-suffix-p ".org" file)
      (dolist (site my/blog-sites)
        ;; A machine without the site directory stays silent: the
        ;; autostart left one line in *Messages*, that is enough.
        (when (and (my/blog--prop site :autostart)
                   (member silo (my/blog--site-silos site))
                   (file-directory-p (my/blog--directory site)))
          (let* ((name (car site))
                 (old (cdr (assoc name my/blog--save-timers))))
            (when (timerp old) (cancel-timer old))
            (setf (alist-get name my/blog--save-timers nil nil #'equal)
                  (run-with-idle-timer
                   3 nil
                   (lambda ()
                     (setq my/blog--save-timers
                           (assoc-delete-all name my/blog--save-timers))
                     (condition-case err
                         (my/blog--start name (list :write t :quiet t))
                       (error (message "Blog, %s: %s" name
                                       (error-message-string err)))))))))))))

(add-hook 'after-save-hook #'my/blog--after-save)

(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer my/blog-autostart-delay nil #'my/blog--autostart)))

;; ============================================================
;; MENU  (C-c n x b)
;; Docs: ~/.emacs.d/function_helper.org::#menu-blog
;; ============================================================

(transient-define-prefix my/blog-menu ()
  "Publish notes as Hugo sites."
  [["Export"
    ("e" "This note"               my/blog-export-current)
    ("d" "Site - dry run"          my/blog-export-all-dry-run)
    ("a" "Site - changes"          my/blog-export-all)
    ("A" "Site - everything"       my/blog-export-all-full)]
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
