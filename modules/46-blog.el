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
;; FILES OUTSIDE THE SILOS
;; -----------------------
;; Any Org file -- function_helper.org, a README -- can be placed on
;; sites by hand, section by section, without a keyword: `f' in the menu
;; picks the file, the sites and the section, and records the choice in
;; `my/blog-extra-files-file' (hugo/extra-files.eld in this repository,
;; readable and editable by hand); `F' takes a file off again.  Such a
;; file is exported like a note.  Its URL comes from its file name, as
;; it has no Denote title, and a file without `#+date:' is dated by its
;; modification time.  A file in a private silo is refused on a site
;; with a server, whatever the list says.
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
;;   - a link to a note on ANOTHER site becomes an absolute link below
;;     that site's `:url', when this site may link there (see
;;     `my/blog--link-sites': a site with a server links only to sites
;;     with a server);
;;   - a link to any other note becomes its description, as plain text.
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
;; SITE FILES FROM THE EMACS REPOSITORY
;; ------------------------------------
;; Hugo configuration, layouts, section title pages and favicons are
;; declared in this repository, under `my/blog-template-directory'
;; (hugo/), in three layers, each overriding the one before:
;;   hugo/common/          copied into every site
;;   hugo/theme/<theme>/   copied into every site using that `:theme'
;;   hugo/sites/<name>/    copied into site <name>
;; The theme layer exists because a hook such as the backlinks partial
;; has a different name and place in every theme.
;; A sync copies every file whose content differs from the site's copy.
;; The site's copy is generated: edits belong in the repository.  A
;; file changed on disk since the last sync (or never synced) is saved
;; to <site>/.template-backups/ before being replaced, and the sync
;; says so.  Files removed from the templates are not removed from the
;; site.  A sync also creates a missing site directory and clones the
;; site's `:theme' when themes/<name> is missing, so a new machine gets
;; a working site from the repository alone.
;; Sync runs before an autostart site is exported and served, before a
;; preview starts and before publishing; `t' in the menu runs it by hand.
;;
;; BACKLINKS
;; ---------
;; After each run the module writes data/blog_backlinks.json in the
;; site: for every page, the pages of the same site that link to it.
;; It already knows every note's links from the incremental state, so
;; this costs no extra reading.  hugo/common/ carries a partial that
;; shows the list under each page.  Links from notes that are not on
;; the site are not counted, so a private note never appears.
;; Rejected: the usual Hugo recipe, a template that searches the raw
;; content of every page for links to the current one.  It needs no
;; Emacs support, but costs pages x pages string searches: for a
;; journal of over 3000 pages, about ten million searches through
;; 11 MB of text on every build.
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
;;   A  export a site (all)       t  sync site files from hugo/
;;   f  place a file on sites     o  site folder in Dired
;;   F  take a placed file off
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
(require 'json)
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
  '(("journal"
     :directory "~/projects/journal-site/"
     :remote nil
     :url "http://localhost:1314/"
     :port 1314
     :theme ("PaperMod" "https://github.com/adityatelange/hugo-PaperMod")
     :autostart t
     :broken-links mark
     :sections (("journal" :keyword "journal" :silos ("journal"))
                ("posts"   :keyword "blog"    :silos ("pks" "docu"))))
    ("docs"
     :directory "~/projects/docs-site/"
     :remote nil
     :url "http://localhost:1315/"
     :port 1315
     :theme ("hugo-book" "https://github.com/alex-shpak/hugo-book")
     :autostart t
     :sections (("docs" :keyword "pubdoc" :silos ("pks" "docu"))))
    ("blog"
     :directory "~/projects/blog/"
     :remote nil
     :url "http://localhost:1313/"
     :port 1313
     :theme ("PaperMod" "https://github.com/adityatelange/hugo-PaperMod")
     :sections (("posts" :keyword "blog" :silos ("pks" "docu")))))
  "Hugo sites notes are published to.
Each entry is (NAME . PLIST):
  :directory     root of the Hugo site, the directory holding hugo.toml;
                 keep it outside the notes tree: a site under git must
                 stay out of Syncthing's reach, and a copy of the
                 journal must not be synced as a second journal
  :remote        rsync destination such as \"user@server:/var/www/blog/\"
                 (trailing slash matters), or nil for a laptop-only site
  :url           address the site is read at; needed for other sites
                 to link to its pages (see `my/blog--link-sites')
  :port          port of `hugo server', default 1313
  :theme         (NAME URL): cloned to themes/NAME when missing
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

(defcustom my/blog-template-directory
  (expand-file-name "hugo/" user-emacs-directory)
  "Directory holding the site files declared in this repository.
common/ is copied into every site, sites/<name>/ into site <name>."
  :type 'directory
  :group 'my/blog)

(defcustom my/blog-extra-files-file
  (expand-file-name "extra-files.eld" my/blog-template-directory)
  "File listing Org files placed on sites by hand, outside the silos.
Each entry is (FILE (SITE . SECTION) ...).  Written by `f' and `F' in
the menu; may be edited by hand."
  :type 'file
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

(defconst my/blog--state-format 2
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
      (user-error "Site %s not found: %s (C-c n x b t creates it)"
                  (car site) dir))
     ((not (seq-some (lambda (name) (file-exists-p (expand-file-name name dir)))
                     my/blog--hugo-config-files))
      (user-error "No Hugo configuration in %s (C-c n x b t writes it)" dir))
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
By keyword and silo, plus any placement in `my/blog-extra-files-file'.
Nil when FILE is not on that site."
  (when (and (stringp file)
             (string-suffix-p ".org" file)
             (file-exists-p file))
    (let ((found '()))
      (when (and (string-prefix-p (my/blog--notes-root) (expand-file-name file))
                 (not (my/blog--excluded-p file)))
        (let ((silo (my/blog--silo-of file))
              (keywords (denote-extract-keywords-from-path file)))
          (dolist (sec (my/blog--sections site))
            (when (and (member silo (plist-get (cdr sec) :silos))
                       (member (plist-get (cdr sec) :keyword) keywords))
              (push (car sec) found)))))
      (dolist (section (my/blog--extra-sections site file))
        (unless (member section found) (push section found)))
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
    (dolist (entry (my/blog--extra-files))
      (when (and (file-exists-p (car entry))
                 (my/blog--extra-sections site (car entry)))
        (push (car entry) files)))
    ;; The order decides which of two colliding URLs is kept: the
    ;; older note's.
    (sort (delete-dups files)
          (lambda (a b) (string< (file-name-nondirectory a)
                                 (file-name-nondirectory b))))))

;; ============================================================
;; FILES PLACED BY HAND
;; ============================================================

(defvar my/blog--extra-cache nil
  "(FILE MTIME . ENTRIES) of the last read of `my/blog-extra-files-file'.
A plan asks for every note whether it was placed by hand; reading the
list once per note would mean thousands of reads per journal export.")

(defun my/blog--extra-files ()
  "Return the entries of `my/blog-extra-files-file', paths expanded.
Each entry is (FILE (SITE . SECTION) ...).  A missing or unreadable
list is an empty one.  Re-read only when the file changes."
  (let ((mtime (my/blog--mtime my/blog-extra-files-file)))
    (if (and my/blog--extra-cache
             (equal (car my/blog--extra-cache) my/blog-extra-files-file)
             (equal (cadr my/blog--extra-cache) mtime))
        (cddr my/blog--extra-cache)
      (let* ((data (and mtime
                        (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents my/blog-extra-files-file)
                              (read (current-buffer)))
                          (error
                           (message "Blog: %s is not a readable list"
                                    my/blog-extra-files-file)
                           nil))))
             (entries (mapcar (lambda (entry)
                                (cons (expand-file-name (car entry)) (cdr entry)))
                              (seq-filter (lambda (entry)
                                            (and (consp entry) (stringp (car entry))))
                                          (and (listp data) data)))))
        (setq my/blog--extra-cache (cons my/blog-extra-files-file (cons mtime entries)))
        entries))))

(defun my/blog--extra-sections (site file)
  "Return the sections of SITE that FILE was placed in by hand.
A placement in a section the site does not have (any more) is ignored;
otherwise its pages would land in a directory nobody prunes."
  (let ((entry (assoc (expand-file-name file) (my/blog--extra-files))))
    (delq nil (mapcar (lambda (placement)
                        (when (and (equal (car placement) (car site))
                                   (assoc (cdr placement) (my/blog--sections site)))
                          (cdr placement)))
                      (cdr entry)))))

(defun my/blog--write-extra-files (entries)
  "Write ENTRIES, a list of (FILE (SITE . SECTION) ...), as the list."
  (let ((entries (sort (seq-filter #'cdr entries)
                       (lambda (a b) (string< (car a) (car b))))))
    (make-directory (file-name-directory my/blog-extra-files-file) t)
    (with-temp-file my/blog-extra-files-file
      (insert ";; -*- mode: lisp-data -*-\n"
              ";; Org files outside the silos, placed on Hugo sites by hand.\n"
              ";; Read by modules/46-blog.el; written by C-c n x b f / F.\n"
              ";; Entry: (FILE (SITE . SECTION) ...)\n(")
      (let ((first t))
        (dolist (entry entries)
          (insert (if first "" "\n "))
          (setq first nil)
          (prin1 (cons (abbreviate-file-name (car entry)) (cdr entry)) (current-buffer))))
      (insert ")\n"))
    ;; Two writes within the file system's time resolution would keep
    ;; the same modification time; forget the cached copy outright.
    (setq my/blog--extra-cache nil)))

;;;###autoload
(defun my/blog-place-file (file site-names section)
  "Place Org FILE on the sites SITE-NAMES, in SECTION of each.
For files outside the silos, which no keyword can reach.  The choice
is recorded in `my/blog-extra-files-file' and replaces any earlier
placement of FILE on those sites.  The page appears at the site's next
export; an autostart site exports at once."
  (interactive
   (let* ((file (expand-file-name
                 (read-file-name "Org file to publish: " nil
                                 (and buffer-file-name
                                      (string-suffix-p ".org" buffer-file-name)
                                      buffer-file-name)
                                 t nil
                                 (lambda (f) (or (file-directory-p f)
                                                 (string-suffix-p ".org" f))))))
          (names (progn (my/blog--check-config) (mapcar #'car my/blog-sites)))
          (sites (completing-read-multiple
                  (format "Sites (comma-separated, default all: %s): "
                          (string-join names ","))
                  names nil t nil nil (string-join names ",")))
          ;; Only sections every chosen site has: one answer for all.
          (common (seq-reduce
                   (lambda (acc name)
                     (seq-intersection
                      acc (mapcar #'car (my/blog--sections (my/blog--site name)))))
                   (cdr sites)
                   (mapcar #'car (my/blog--sections (my/blog--site (car sites)))))))
     (unless common
       (user-error "The chosen sites share no section"))
     (list file sites (completing-read "Section: " common nil t))))
  (unless (string-suffix-p ".org" file)
    (user-error "Only Org files can be exported: %s" file))
  (let* ((path (expand-file-name file))
         (entries (my/blog--extra-files))
         (old (cdr (assoc path entries)))
         (kept (seq-remove (lambda (p) (member (car p) site-names)) old))
         (placements (append kept (mapcar (lambda (name) (cons name section))
                                          site-names))))
    (my/blog--write-extra-files
     (cons (cons path placements) (assoc-delete-all path entries)))
    (message "%s -> %s"
             (file-name-nondirectory path)
             (mapconcat (lambda (p) (format "%s/%s" (car p) (cdr p))) placements ", "))
    (my/blog--export-autostart-sites site-names)))

;;;###autoload
(defun my/blog-unplace-file (file)
  "Take FILE, placed by hand, off every site.
Its pages disappear at each site's next export; an autostart site
exports at once."
  (interactive
   (let ((entries (my/blog--extra-files)))
     (unless entries (user-error "No files placed by hand"))
     (list (completing-read "Take off the sites: "
                            (mapcar (lambda (e) (abbreviate-file-name (car e))) entries)
                            nil t))))
  (let* ((path (expand-file-name file))
         (entries (my/blog--extra-files))
         (sites (mapcar #'car (cdr (assoc path entries)))))
    (my/blog--write-extra-files (assoc-delete-all path entries))
    (message "%s taken off %s" (file-name-nondirectory path) (string-join sites ", "))
    (my/blog--export-autostart-sites sites)))

(defun my/blog--export-autostart-sites (site-names)
  "Start a background export of each autostart site among SITE-NAMES."
  (dolist (name site-names)
    (let ((site (assoc name my/blog-sites)))
      (when (and site
                 (my/blog--prop site :autostart)
                 (file-directory-p (my/blog--directory site)))
        (condition-case err
            (my/blog--start name (list :write t :quiet t))
          (error (message "Blog, %s: %s" name (error-message-string err))))))))

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
  "Return the URL slug of FILE according to `my/blog-url-source'.
A file that is not a Denote note has neither identifier nor title in
its name; its whole base name, transliterated, is the slug."
  (let ((id (denote-retrieve-filename-identifier file)))
    (if (null id)
        (my/blog--ascii (file-name-base file))
      (let* ((title (denote-retrieve-filename-title file))
             (from-title (and title (my/blog--ascii title))))
        (if (and (eq my/blog-url-source 'title)
                 from-title
                 (not (string-empty-p from-title)))
            from-title
          (downcase id))))))

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

(defvar my/blog--foreign-index-cache nil
  "Alist of site name -> (MTIME . INDEX) read from other sites' state.")

(defun my/blog--site-url (site)
  "Return the `:url' of SITE without its trailing slash, or nil."
  (when-let* ((url (my/blog--prop site :url)))
    (string-remove-suffix "/" url)))

(defun my/blog--link-sites (site)
  "Return the other sites SITE may link to, in `my/blog-sites' order.
A site needs a `:url' to be linked to.  A site with a `:remote' links
only to sites that also have one: a page on a server must not point
at a laptop-only site, which its readers cannot reach and which may
hold private notes."
  (seq-filter (lambda (other)
                (and (not (equal (car other) (car site)))
                     (my/blog--site-url other)
                     (or (not (my/blog--prop site :remote))
                         (my/blog--prop other :remote))))
              my/blog-sites))

(defun my/blog--published-index (site)
  "Return identifier -> (SECTION . SLUG) of SITE as of its last run.
Read from the site's state file, cached by modification time: what
another site has actually exported, not what it would export now."
  (let* ((path (my/blog--state-path site))
         (mtime (my/blog--mtime path))
         (hit (cdr (assoc (car site) my/blog--foreign-index-cache))))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let ((index (my/blog--alist-to-hash
                    (plist-get (my/blog--read-state site) :index))))
        (setf (alist-get (car site) my/blog--foreign-index-cache nil nil #'equal)
              (cons mtime index))
        index))))

(defun my/blog--targets (site index)
  "Return identifier -> (SECTION SLUG BASE) for links from SITE.
INDEX is the site's own; BASE is nil for its pages.  A note on no own
page but on a site from `my/blog--link-sites' gets the first such
site's page, BASE being that site's `:url'."
  (let ((targets (make-hash-table :test #'equal :size (hash-table-count index))))
    (maphash (lambda (id page) (puthash id (list (car page) (cdr page) nil) targets))
             index)
    (dolist (other (my/blog--link-sites site))
      (let ((base (my/blog--site-url other)))
        (maphash (lambda (id page)
                   (unless (gethash id targets)
                     (puthash id (list (car page) (cdr page) base) targets)))
                 (my/blog--published-index other))))
    targets))

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
  :targets  identifier -> (SECTION SLUG BASE) of every note a link may
            reach: the site's own (BASE nil) and those of other sites
            this site may link to (BASE their `:url')
  :index-changed  non-nil when :index differs from the last run's
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
         (old-targets (my/blog--alist-to-hash (plist-get state :targets)))
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
         ((and (my/blog--prop site :remote)
               (member (my/blog--silo-of file) my/blog-private-silos))
          (push (list file "in a private silo, and this site has a server")
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
    (let* ((targets (my/blog--targets site index))
           (changed (my/blog--changed-ids old-targets targets))
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
            :targets targets
            :index-changed (and (my/blog--changed-ids old-index index) t)
            :cache cache
            :stamps stamps
            :full full))))

;; ============================================================
;; EXPORT OF ONE NOTE
;; ============================================================

(defun my/blog--link-export-function (targets)
  "Return an `:export' function for `denote:' links resolved by TARGETS.
TARGETS maps identifiers to (SECTION SLUG BASE), see `my/blog--targets'.
A link to a page of the same site (BASE nil) is written in
`my/blog-link-style'; a link to another site's page is an absolute
link below that site's BASE; `::#custom-id' anchors are kept.  Any
other link becomes its description alone, so nothing about a note that
is not published leaves the machine except the words the page itself
uses for it.  A format other than `md' gets the description too: the
function is only installed for Hugo exports."
  (lambda (link description format)
    (let* ((parts (split-string link "::"))
           (search (cadr parts))
           (target (gethash (car parts) targets))
           (text (or description "")))
      (if (and target (eq format 'md))
          (let* ((section (nth 0 target))
                 (slug (nth 1 target))
                 (base (nth 2 target))
                 (label (if (string-empty-p text) slug text))
                 (anchor (if (and search (string-prefix-p "#" search)) search "")))
            (cond
             (base (format "[%s](%s/%s/%s/%s)" label base section slug anchor))
             ((eq my/blog-link-style 'relref)
              (format "[%s]({{< relref \"/%s/%s%s\" >}})" label section slug anchor))
             (t (format "[%s](/%s/%s/%s)" label section slug anchor))))
        text))))

(defun my/blog--link-parameters (targets)
  "Return `org-link-parameters' with the site's export for `denote'."
  (let* ((params (copy-alist org-link-parameters))
         (denote-params (copy-sequence (cdr (assoc "denote" params)))))
    (cons (cons "denote" (plist-put denote-params :export
                                    (my/blog--link-export-function targets)))
          (assoc-delete-all "denote" params))))

(defun my/blog--export-file (site file section slug targets)
  "Export FILE to SECTION of SITE as SLUG, resolving links through TARGETS.
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
         (org-link-parameters (my/blog--link-parameters targets)))
    (with-temp-buffer
      (insert (format "#+export_file_name: %s\n" slug))
      (insert-file-contents file)
      (let ((case-fold-search t))
        ;; A file without a date (function_helper.org) would sort after
        ;; every dated page; its modification time is the closest fact.
        (unless (save-excursion (goto-char (point-min))
                                (re-search-forward "^#\\+date:" nil t))
          (insert (format-time-string "#+date: [%Y-%m-%d %a %H:%M]\n"
                                      (file-attribute-modification-time
                                       (file-attributes file))))))
      (save-excursion
        (goto-char (point-max))
        ;; The theme draws the table of contents; one written by ox-hugo
        ;; from a file's own `toc:' option would appear a second time.
        ;; At the end, because a later #+options line overrides an
        ;; earlier one.
        (insert "\n#+options: toc:nil\n"))
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
      (my/blog--start name (list :write t :quiet t)))
    ;; Pages appeared, went or moved: autostart sites that link here
    ;; may have links to turn into text or back.
    (when (and (plist-get job :write) (plist-get plan :index-changed))
      (my/blog--export-autostart-sites
       (mapcar #'car
               (seq-filter (lambda (other)
                             (member (car site)
                                     (mapcar #'car (my/blog--link-sites other))))
                           my/blog-sites))))))

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
           :targets (my/blog--hash-to-alist (plist-get plan :targets))
           :cache (my/blog--hash-to-alist (plist-get plan :cache))
           :stamps (my/blog--hash-to-alist (plist-get plan :stamps))
           :retry (mapcar #'car (plist-get job :failed))))
    (my/blog--write-backlinks site plan))
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
         (targets (plist-get plan :targets)))
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
              (my/blog--export-file site file (nth 1 entry) (nth 2 entry) targets)
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
                                (plist-get plan :targets))
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
;; SITE FILES FROM THE REPOSITORY
;; ============================================================

(defconst my/blog--template-record ".blog-templates.eld"
  "File in each site root recording what the last sync wrote.")

(defconst my/blog--template-backups ".template-backups"
  "Directory in each site root keeping files replaced by a sync.
At the root and starting with a dot, so Hugo reads nothing from it.")

(defun my/blog--sha1 (file)
  "Return the SHA-1 of the bytes of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha1 (current-buffer))))

(defun my/blog--read-data (file)
  "Return the Lisp object stored in FILE, or nil when it is unreadable."
  (when (file-readable-p file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (read (current-buffer)))
      (error nil))))

(defun my/blog--template-files (site)
  "Return (RELATIVE . SOURCE) for every template file of SITE.
Three layers, each overriding the one before file by file: common/,
theme/<name of the site's :theme>/, sites/<site name>/."
  (let ((table (make-hash-table :test #'equal))
        (result '())
        (theme (car (my/blog--prop site :theme))))
    (dolist (dir (list (expand-file-name "common" my/blog-template-directory)
                       (and theme
                            (expand-file-name (concat "theme/" theme)
                                              my/blog-template-directory))
                       (expand-file-name (concat "sites/" (car site))
                                         my/blog-template-directory)))
      (when (and dir (file-directory-p dir))
        (dolist (file (directory-files-recursively dir ""))
          (puthash (file-relative-name file dir) file table))))
    (maphash (lambda (rel src) (push (cons rel src) result)) table)
    (sort result (lambda (a b) (string< (car a) (car b))))))

(defun my/blog--sync-templates (site)
  "Copy the template files of SITE into its directory, creating it.
Only files whose content differs are written.  A site file changed
since the last sync, or present before the first one, is copied to
`my/blog--template-backups' first.  Returns (WRITTEN . BACKED-UP),
two lists of relative paths."
  (let* ((dir (my/blog--directory site))
         (record-file (expand-file-name my/blog--template-record dir))
         (record (my/blog--read-data record-file))
         (stamp (format-time-string "%Y%m%d-%H%M%S"))
         (new-record '())
         (written '())
         (backed-up '()))
    (make-directory dir t)
    (dolist (entry (my/blog--template-files site))
      (let* ((rel (car entry))
             (dst (expand-file-name rel dir))
             (src-sum (my/blog--sha1 (cdr entry)))
             (dst-sum (and (file-exists-p dst) (my/blog--sha1 dst))))
        (unless (equal src-sum dst-sum)
          (when (and dst-sum (not (equal dst-sum (cdr (assoc rel record)))))
            (let ((backup (expand-file-name (concat rel "." stamp)
                                            (expand-file-name my/blog--template-backups dir))))
              (make-directory (file-name-directory backup) t)
              (copy-file dst backup t)
              (push rel backed-up)))
          (make-directory (file-name-directory dst) t)
          (copy-file (cdr entry) dst t)
          (push rel written))
        (push (cons rel src-sum) new-record)))
    (with-temp-file record-file
      (let ((print-length nil) (print-level nil))
        (insert ";; Written by 46-blog.el: what the last template sync wrote.\n")
        (prin1 (nreverse new-record) (current-buffer))
        (insert "\n")))
    ;; ox-hugo needs static/ for images; see `my/blog--check-site'.
    (make-directory (expand-file-name "static" dir) t)
    (cons (nreverse written) (nreverse backed-up))))

(defun my/blog--ensure-theme (site then)
  "Clone the `:theme' of SITE when it is missing, then call THEN.
THEN receives non-nil when the theme is present afterwards."
  (let* ((theme (my/blog--prop site :theme))
         (target (and theme (expand-file-name (concat "themes/" (car theme))
                                              (my/blog--directory site)))))
    (cond
     ((or (null theme) (file-directory-p target))
      (funcall then t))
     ((not (executable-find "git"))
      (message "%s: theme %s missing and git not found" (car site) (car theme))
      (funcall then nil))
     (t
      (message "%s: cloning theme %s..." (car site) (car theme))
      (make-process
       :name (format "blog-theme-%s" (car site))
       :buffer (get-buffer-create (format "*Blog theme: %s*" (car site)))
       :command (list "git" "clone" "--depth" "1" (cadr theme) target)
       :noquery t
       :sentinel (lambda (proc _event)
                   (when (memq (process-status proc) '(exit signal))
                     (let ((ok (zerop (process-exit-status proc))))
                       (message "%s: theme %s %s" (car site) (car theme)
                                (if ok "installed" "clone FAILED"))
                       (funcall then ok)))))))))

(defun my/blog--sync-message (site result quiet)
  "Report RESULT of `my/blog--sync-templates' for SITE.
With QUIET, say nothing when nothing was written."
  (let ((written (car result))
        (backed-up (cdr result)))
    (when (or written backed-up (not quiet))
      (message "%s: %s%s"
               (car site)
               (if written
                   (format "site files updated: %s" (string-join written ", "))
                 "site files up to date")
               (if backed-up
                   (format "; local edits of %s kept in %s/"
                           (string-join backed-up ", ") my/blog--template-backups)
                 "")))))

(defun my/blog--prepare-site (site then &optional quiet)
  "Sync the site files of SITE and install its theme, then call THEN.
THEN receives non-nil when the site is ready.  With QUIET, report only
changes."
  (my/blog--sync-message site (my/blog--sync-templates site) quiet)
  (my/blog--ensure-theme site then))

;;;###autoload
(defun my/blog-sync-site (site-name)
  "Copy the site files of SITE-NAME from the repository, install its theme.
Creates the site directory when it is missing.  A running `hugo server'
notices the new files by itself."
  (interactive (list (my/blog--read-site)))
  (my/blog--prepare-site (my/blog--site site-name) #'ignore))

;; ============================================================
;; BACKLINKS
;; ============================================================

(defun my/blog--write-backlinks (site plan)
  "Write data/blog_backlinks.json of SITE from PLAN.
Maps each page path /<section>/<slug> to the sorted paths of the pages
of the same site that link to it.  The file is written only when its
content changes: every write makes `hugo server' rebuild."
  (let ((index (plist-get plan :index))
        (cache (plist-get plan :cache))
        (table (make-hash-table :test #'equal))
        (path (expand-file-name "data/blog_backlinks.json" (my/blog--directory site))))
    (dolist (entry (plist-get plan :ready))
      (let ((source (format "/%s/%s" (nth 1 entry) (nth 2 entry))))
        (dolist (id (nth 2 (gethash (nth 0 entry) cache)))
          (when-let* ((target (gethash id index)))
            (let ((key (format "/%s/%s" (car target) (cdr target))))
              (unless (equal key source)
                (puthash key (cons source (gethash key table)) table)))))))
    (let* ((keys (sort (hash-table-keys table) #'string<))
           (alist (mapcar (lambda (key)
                            (cons key (vconcat (sort (delete-dups (gethash key table))
                                                     #'string<))))
                          keys))
           (json (if alist (json-encode alist) "{}"))
           (old (and (file-readable-p path)
                     (with-temp-buffer (insert-file-contents path) (buffer-string)))))
      (unless (equal json old)
        (make-directory (file-name-directory path) t)
        (with-temp-file path (insert json))))))

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
    (my/blog--check-program my/blog-hugo-program)
    (my/blog--prepare-site
     site
     (lambda (ok)
       (when ok
         (my/blog--check-site site)
         (if (my/blog--serve site-name t)
             (progn
               ;; The first build takes a moment; opening the page at
               ;; once shows a connection error instead.
               (run-at-time 2 nil #'browse-url url)
               (message "Hugo server for %s starting on %s" site-name url))
           (browse-url url)))))))

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
    ;; The published configuration is the repository's, not whatever
    ;; the site directory happens to hold.
    (my/blog--sync-templates site)
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
          ;; Hugo first: without it, nothing is created on disk.
          (my/blog--check-program my/blog-hugo-program)
          (my/blog--prepare-site
           site
           (lambda (ok)
             (if (not ok)
                 (let ((inhibit-message t))
                   (message "Blog autostart, %s: theme could not be installed" name))
               (condition-case err
                   (my/blog--start name
                                   (list :write t :quiet t
                                         :on-done (lambda (_ok) (my/blog--serve name nil))))
                 (error
                  (let ((inhibit-message t))
                    (message "Blog autostart, %s: %s" name (error-message-string err)))))))
           t))
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
  (when-let* ((file buffer-file-name))
    (when (string-suffix-p ".org" file)
      (dolist (site my/blog-sites)
        ;; A machine without the site directory stays silent: the
        ;; autostart left one line in *Messages*, that is enough.
        (when (and (my/blog--prop site :autostart)
                   (or (member (my/blog--silo-of file) (my/blog--site-silos site))
                       (my/blog--extra-sections site file))
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
    ("f" "Place a file on sites"   my/blog-place-file)
    ("F" "Take a placed file off"  my/blog-unplace-file)
    ("d" "Site - dry run"          my/blog-export-all-dry-run)
    ("a" "Site - changes"          my/blog-export-all)
    ("A" "Site - everything"       my/blog-export-all-full)]
   ["Site"
    ("v" "Preview (hugo server)"   my/blog-preview)
    ("s" "Stop preview"            my/blog-preview-stop)
    ("p" "Publish to server"       my/blog-publish)
    ("t" "Sync site files"         my/blog-sync-site)]
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
