;;; 47-repo-docs.el --- Markdown docs of a git repository as a Hugo site -*- lexical-binding: t; -*-
;;; Commentary:
;; The Markdown files of one git repository -- by default the NixOS
;; configuration in ~/nixos -- served as a separate, read-only Hugo site
;; with the Geekdoc theme (https://github.com/thegeeklab/hugo-geekdoc),
;; laid out by the repository's own folders.  The files are edited where
;; they are, in the repository, and committed there by hand; the site is
;; only a way of reading them.
;;
;; WHY NOT A DENOTE SILO
;; ---------------------
;; A silo is a directory under ~/notes/: synced by Syncthing,
;; auto-committed on idle by 07-git.el, and full of Denote file names
;; that the silo commands rename, index and count.  The NixOS repository
;; is none of that -- a separate git repository whose commits are made
;; deliberately, with names such as README.md that Denote does not
;; recognise.  Treating it as a silo would hand it to machinery built to
;; change files.  It is therefore a SOURCE: files are found with
;; `my/repo-docs-find' and opened as they are, and nothing here writes to
;; the repository.
;;
;; THE SITE IS GENERATED, NOT MOUNTED
;; ----------------------------------
;; Hugo could mount the repository as its content directory, but the
;; files would not render well as they stand:
;;   - none has front matter, and Geekdoc prints the page title as an
;;     H1, so every page would show either no title or its H1 twice;
;;   - seven files are called README.md, which Hugo turns into seven
;;     pages titled "README" (the "thirty READMEs" problem);
;;   - fifty links point at other .md files by relative path, and
;;     Geekdoc's link render hook passes them through unchanged, so every
;;     one of them would be a 404.
;; So each run writes a content directory into the site, derived from the
;; repository and owned by this module (anything else in it is deleted):
;;   - a README.md becomes the page of its FOLDER (_index.md), titled
;;     with the folder name and a trailing slash, e.g. "devices/";
;;     the README's own H1 stays in the text as an H2 under it, unless
;;     it only repeats the folder name;
;;   - a folder without a README still appears, titled the same way, with
;;     Geekdoc's `toc-tree' listing what is inside;
;;   - every other file becomes a page titled with its first H1, which is
;;     taken out of the text; a file without an H1 is titled with its
;;     name;
;;   - in each folder, subfolders come first, then files in file-name
;;     order (the guide's 01-..08- prefixes give the reading order);
;;   - relative links to .md files and to folders are rewritten to the
;;     URL of the page they become, anchors kept; links Hugo would not
;;     find are left as written and listed in the report.
;; Above the text of every page with headings sits its table of
;; contents (`my/repo-docs-toc'), from Geekdoc's templates overridden in
;; the site's layouts/ -- Geekdoc has no hook there.
;;
;; URLs are the repository path in lower case: docs/BACKUPS.md is read at
;; /docs/backups/.  They are written into each page's `url', so a link
;; never depends on Hugo's own path rules.
;;
;; Files are those git would commit: tracked, plus untracked but not
;; ignored, so a new document shows up before its first `git add'.
;;
;; KEEPING IT CURRENT
;; ------------------
;; `my/repo-docs-preview' regenerates the site, starts `hugo server'
;; and opens the page of the current file (or the home page).  While
;; the server runs, saving any Markdown file of the repository
;; regenerates the site, and the server reloads the browser.  Only files
;; whose content changed are rewritten.
;;
;; THEME
;; -----
;; Geekdoc is installed from its release bundle, not cloned: the
;; repository holds sources that need an npm build, the bundle holds the
;; built assets (Geekdoc's own "Getting started").  The bundle is fetched
;; with `url-copy-file' and unpacked with tar into themes/hugo-geekdoc
;; when that directory is missing.  Geekdoc 4.x needs Hugo 0.160 or
;; newer.
;;
;; MENU (C-c n x r)
;; ----------------
;;   f  find a document       v  preview in the browser
;;   g  regenerate the site   s  stop the preview
;;   o  site folder           l  last report
;;
;; Docs: ~/.emacs.d/function_helper.org::#repo-docs

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'url-util)
(require 'json)
(require 'transient)

;; ============================================================
;; SETTINGS
;; ============================================================

(defgroup my/repo-docs nil
  "Markdown documentation of a git repository as a Hugo site."
  :group 'mypks-publishing)

(defcustom my/repo-docs-repository "~/nixos/"
  "Git repository whose Markdown files are shown."
  :type 'directory
  :group 'my/repo-docs)

(defcustom my/repo-docs-site-directory "~/projects/nixos-docs-site/"
  "Hugo site generated from `my/repo-docs-repository'.
Created when missing.  Everything in it is generated or downloaded, so
it is kept outside the notes tree and outside any repository."
  :type 'directory
  :group 'my/repo-docs)

(defcustom my/repo-docs-title "nixos"
  "Title of the site, shown in its header."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-port 1316
  "Port of `hugo server'.
1313-1315 are taken by the sites of 46-blog.el."
  :type 'integer
  :group 'my/repo-docs)

(defcustom my/repo-docs-hugo-program "hugo"
  "Hugo executable."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-theme-url
  "https://github.com/thegeeklab/hugo-geekdoc/releases/latest/download/hugo-geekdoc.tar.gz"
  "Release bundle of the Geekdoc theme, unpacked into themes/hugo-geekdoc."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-toc t
  "Non-nil shows a table of contents above the text of each page.
Only pages with headings below the title get one."
  :type 'boolean
  :group 'my/repo-docs)

(defcustom my/repo-docs-regenerate-on-save t
  "Non-nil regenerates the site when a Markdown file of the repository
is saved while the preview server runs."
  :type 'boolean
  :group 'my/repo-docs)

(defconst my/repo-docs-report-buffer "*Repo docs*"
  "Buffer holding the report of the last regeneration.")

(defconst my/repo-docs--server-buffer "*Repo docs server*"
  "Buffer of the `hugo server' process.")

(defconst my/repo-docs--theme-name "hugo-geekdoc"
  "Directory name of the theme under themes/.")

;; ============================================================
;; PATHS
;; ============================================================

(defun my/repo-docs--repo ()
  "Return the repository root as an absolute directory name."
  (file-name-as-directory (expand-file-name my/repo-docs-repository)))

(defun my/repo-docs--site ()
  "Return the site root as an absolute directory name."
  (file-name-as-directory (expand-file-name my/repo-docs-site-directory)))

(defun my/repo-docs--content-dir ()
  "Return the generated content directory of the site."
  (expand-file-name "content/" (my/repo-docs--site)))

(defun my/repo-docs--markdown-p (path)
  "Non-nil when PATH names a Markdown file."
  (let ((case-fold-search t))
    (string-match-p "\\.md\\'" path)))

(defun my/repo-docs--readme-p (rel)
  "Non-nil when repository path REL is a README.md."
  (string-equal-ignore-case (file-name-nondirectory rel) "README.md"))

(defun my/repo-docs--dir-of (rel)
  "Return the directory part of REL without a trailing slash, \"\" at the root."
  (directory-file-name (or (file-name-directory rel) "")))

(defun my/repo-docs--files ()
  "Return the repository's Markdown files, relative and sorted.

The files git would commit: tracked ones, plus untracked ones that are
not ignored.  Signals a `user-error' when the repository is missing or
git fails, since a silently empty site would look like deleted docs."
  (let ((repo (my/repo-docs--repo)))
    (unless (file-directory-p repo)
      (user-error "Repository %s does not exist" repo))
    (with-temp-buffer
      (let* ((default-directory repo)
             (status (process-file "git" nil t nil
                                   "-c" "core.quotePath=false"
                                   "ls-files" "-z" "--cached" "--others"
                                   "--exclude-standard")))
        (unless (eq status 0)
          (user-error "git ls-files failed in %s: %s"
                      repo (string-trim (buffer-string))))
        (sort (seq-filter
               (lambda (rel)
                 (and (my/repo-docs--markdown-p rel)
                      (file-regular-p (expand-file-name rel repo))))
               (delete-dups (split-string (buffer-string) "\0" t)))
              #'string<)))))

;; ============================================================
;; PAGE MAP: repository path -> content file and URL
;; ============================================================
;; Built once per run from the file list alone, so that every link can
;; be rewritten before any page is written.

(defun my/repo-docs--url-of-dir (dir)
  "Return the URL of the page of folder DIR (\"\" for the root)."
  (if (string-empty-p dir) "/" (concat "/" (downcase dir) "/")))

(defun my/repo-docs--sections (files)
  "Return every folder that contains, at any depth, one of FILES.
The root is \"\"; the list is sorted with parents before children."
  (let ((dirs (list "")))
    (dolist (rel files)
      (let ((dir (my/repo-docs--dir-of rel)))
        (while (not (string-empty-p dir))
          (push dir dirs)
          (setq dir (my/repo-docs--dir-of dir)))))
    (sort (delete-dups dirs) #'string<)))

(defun my/repo-docs--map (files)
  "Return a hash table describing the pages made from FILES.

Keys are repository paths of files and of folders (without trailing
slash, \"\" for the root).  Each value is a plist:
  :content  content-relative path of the generated file
  :url      URL of the page
  :file     repository path of the source file, or nil for a folder
            without a README
  :section  non-nil for a folder page."
  (let ((map (make-hash-table :test #'equal)))
    (dolist (dir (my/repo-docs--sections files))
      (puthash dir
               (list :content (if (string-empty-p dir)
                                  "_index.md"
                                (concat (downcase dir) "/_index.md"))
                     :url (my/repo-docs--url-of-dir dir)
                     :file nil
                     :section t)
               map))
    (dolist (rel files)
      (if (my/repo-docs--readme-p rel)
          ;; The README is the folder's page: same content file and URL,
          ;; now with a source.  Both keys lead to it, so a link to the
          ;; folder and a link to its README.md land on the same page.
          (let ((entry (plist-put (copy-sequence
                                   (gethash (my/repo-docs--dir-of rel) map))
                                  :file rel)))
            (puthash (my/repo-docs--dir-of rel) entry map)
            (puthash rel entry map))
        (let ((stem (downcase (file-name-sans-extension rel))))
          (puthash rel
                   (list :content (concat stem ".md")
                         :url (concat "/" stem "/")
                         :file rel
                         :section nil)
                   map))))
    map))

(defun my/repo-docs--collisions (map)
  "Return lists of repository paths that MAP sends to one content file.
Two files differing only in letter case collide, since URLs are lower
case."
  (let ((by-content (make-hash-table :test #'equal))
        collisions)
    (maphash (lambda (key entry)
               (when (plist-get entry :file)
                 (unless (plist-get entry :section)
                   (push key (gethash (plist-get entry :content) by-content)))))
             map)
    (maphash (lambda (_content keys)
               (when (cdr keys) (push (sort keys #'string<) collisions)))
             by-content)
    collisions))

;; ============================================================
;; TEXT: title, H1, links
;; ============================================================

(defconst my/repo-docs--fence-regexp "^ \\{0,3\\}\\(```+\\|~~~+\\)"
  "Opening or closing line of a fenced code block.")

(defconst my/repo-docs--h1-regexp "^# +\\(.*?\\)[ \t]*#*[ \t]*$"
  "ATX level-1 heading; group 1 is its text.")

(defun my/repo-docs--resolve (target source-rel map)
  "Return the URL replacing link TARGET found in SOURCE-REL, or nil.

Only relative targets are considered: a scheme, an absolute path or a
bare anchor is left alone (nil).  The path part is resolved against the
folder of SOURCE-REL; a target outside the repository, or one MAP does
not know, also gives nil.  The anchor, if any, is kept."
  (unless (or (string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*:" target)
              (string-prefix-p "#" target)
              (string-prefix-p "/" target))
    (let* ((hash (string-search "#" target))
           (path (url-unhex-string (substring target 0 hash)))
           (anchor (if hash (substring target hash) ""))
           ;; A fake root keeps `expand-file-name' from touching the
           ;; real file system and makes "outside the repository"
           ;; detectable.
           (root "/repo-docs-root/")
           (abs (expand-file-name path
                                  (concat root (or (file-name-directory
                                                    source-rel)
                                                   ""))))
           (rel (and (string-prefix-p root abs)
                     (directory-file-name (substring abs (length root)))))
           (entry (and rel (gethash rel map))))
      (when entry
        (concat (plist-get entry :url) anchor)))))

(defun my/repo-docs--rewrite-links (line source-rel map unresolved)
  "Return LINE with relative links rewritten for SOURCE-REL using MAP.

Inline links `](target)' and reference definitions `[id]: target' are
rewritten.  A relative target that ends in .md or names a folder and
cannot be resolved is pushed onto the list in the cdr of UNRESOLVED
as (SOURCE-REL . TARGET)."
  (let ((rewrite
         (lambda (target)
           (or (my/repo-docs--resolve target source-rel map)
               (progn
                 (when (and (not (string-match-p
                                  "\\`\\([a-zA-Z][a-zA-Z0-9+.-]*:\\|#\\|/\\)"
                                  target))
                            (my/repo-docs--markdown-p
                             (car (split-string target "#"))))
                   (push (cons source-rel target) (cdr unresolved)))
                 target)))))
    (setq line
          (replace-regexp-in-string
           "](\\([^)[:space:]]+\\)\\([ \t]+\"[^\"]*\"\\)?)"
           (lambda (match)
             (concat "](" (funcall rewrite (match-string 1 match))
                     (or (match-string 2 match) "") ")"))
           line t t))
    (if (string-match "\\`\\( \\{0,3\\}\\[[^]]+\\]:[ \t]+\\)\\([^[:space:]]+\\)\\(.*\\)\\'"
                      line)
        (concat (match-string 1 line)
                (funcall rewrite (match-string 2 line))
                (match-string 3 line))
      line)))

(defun my/repo-docs--transform (text source-rel map unresolved &optional section-label)
  "Return (TITLE . BODY) for TEXT, the content of SOURCE-REL.

TITLE is the first H1 outside code blocks, or nil.  For a regular page
\(SECTION-LABEL nil) that H1 is removed from BODY, since Geekdoc prints
the title itself.  For a folder page SECTION-LABEL is the folder's title:
the H1 is removed when it only repeats the folder name, and otherwise
kept as an H2 under it.

Links are rewritten line by line outside fenced code blocks; see
`my/repo-docs--rewrite-links'."
  (let ((fence nil)
        (title nil)
        (out nil))
    (dolist (line (split-string text "\n"))
      (cond
       ;; Fences: a closing fence must use the opening fence's character
       ;; and be at least as long.
       ((string-match my/repo-docs--fence-regexp line)
        (let ((marker (match-string 1 line)))
          (cond
           ((null fence) (setq fence marker))
           ((and (eq (aref marker 0) (aref fence 0))
                 (>= (length marker) (length fence))
                 (string-match-p (concat "\\`[ \t]*" (regexp-quote marker)
                                         "[ \t]*\\'")
                                 line))
            (setq fence nil))))
        (push line out))
       (fence
        (push line out))
       ((and (null title) (string-match my/repo-docs--h1-regexp line))
        (setq title (match-string 1 line))
        (when section-label
          (let ((bare (lambda (s)
                        (downcase (string-trim s "[`/ \t]*" "[`/ \t]*")))))
            (unless (equal (funcall bare title) (funcall bare section-label))
              (push (concat "#" line) out)))))
       (t
        (push (my/repo-docs--rewrite-links line source-rel map unresolved)
              out))))
    (cons title
          (string-trim-left (string-join (nreverse out) "\n") "\n+"))))

;; ============================================================
;; WRITING THE SITE
;; ============================================================

(defun my/repo-docs--front-matter (fields)
  "Return YAML front matter for FIELDS, a list of (KEY . VALUE).
Strings are written as JSON strings, which YAML reads as double-quoted
scalars, so a title with a colon or quotes needs no special care."
  (concat "---\n"
          (mapconcat (lambda (field)
                       (format "%s: %s" (car field)
                               (if (stringp (cdr field))
                                   (json-encode-string (cdr field))
                                 (cdr field))))
                     (seq-filter #'cdr fields)
                     "\n")
          "\n---\n\n"))

(defun my/repo-docs--weights (map)
  "Return a hash table of repository key -> weight for the pages in MAP.
Within a folder, subfolders come first, sorted by name, then files in
file-name order.  The README of a folder is the folder's own page and
takes no place among its siblings."
  (let ((children (make-hash-table :test #'equal))
        (weights (make-hash-table :test #'equal)))
    (maphash
     (lambda (key entry)
       (unless (or (string-empty-p key)
                   ;; A README key and its folder key share one entry;
                   ;; only the folder key counts as a child.
                   (and (plist-get entry :section)
                        (my/repo-docs--markdown-p key)))
         (push key (gethash (my/repo-docs--dir-of key) children))))
     map)
    (maphash
     (lambda (_parent keys)
       (let ((sorted (sort keys
                           (lambda (a b)
                             (let ((sa (plist-get (gethash a map) :section))
                                   (sb (plist-get (gethash b map) :section)))
                               (if (eq (not sa) (not sb))
                                   (string< (downcase a) (downcase b))
                                 sa)))))
             (weight 0))
         (dolist (key sorted)
           (puthash key (setq weight (+ weight 10)) weights))))
     children)
    weights))

(defun my/repo-docs--page-text (key entry map weights unresolved)
  "Return the full text of the generated file for KEY and its ENTRY."
  (let* ((repo (my/repo-docs--repo))
         (file (plist-get entry :file))
         (section (plist-get entry :section))
         (label (and section
                     (if (string-empty-p key)
                         my/repo-docs-title
                       (concat (file-name-nondirectory key) "/"))))
         (parsed (and file
                      (my/repo-docs--transform
                       (with-temp-buffer
                         (insert-file-contents (expand-file-name file repo))
                         (buffer-string))
                       file map unresolved
                       (and section (not (string-empty-p key)) label))))
         (title (cond
                 ;; The home page keeps the README's title: there is no
                 ;; folder name worth showing at the root.
                 ((and section (string-empty-p key))
                  (or (car parsed) label))
                 (section label)
                 (t (or (car parsed)
                        (file-name-sans-extension
                         (file-name-nondirectory key)))))))
    (concat
     (my/repo-docs--front-matter
      `(("title" . ,title)
        ("weight" . ,(gethash key weights))
        ;; Folder pages take their URL from their place in content/,
        ;; which is already the lower-case repository path.
        ("url" . ,(unless section (plist-get entry :url)))
        ("sourcePath" . ,file)))
     (if parsed
         (cdr parsed)
       ;; A folder without a README: let the theme list its contents.
       "{{< toc-tree >}}")
     "\n")))

(defun my/repo-docs--hugo-config ()
  "Return the hugo.toml of the site.
Values follow Geekdoc's documented configuration."
  (format "baseURL = %s
title = %s
theme = %s
pluralizeListTitles = false
disablePathToLower = true
enableRobotsTXT = false
disableKinds = [\"taxonomy\", \"term\", \"RSS\"]

[markup.goldmark.renderer]
  # Geekdoc needs raw HTML for nested shortcodes such as toc-tree.
  unsafe = true

[markup.tableOfContents]
  # The H1 becomes the page title and leaves the text, so the table of
  # contents starts at H2.
  startLevel = 2
  endLevel = 4

[params]
  geekdocCollapseAllSections = true
  geekdocBreadcrumb = true
  geekdocSearch = true
  geekdocToC = 4
  repoDocsToC = %s
"
          (json-encode-string (format "http://localhost:%d/" my/repo-docs-port))
          (json-encode-string my/repo-docs-title)
          (json-encode-string my/repo-docs--theme-name)
          (if my/repo-docs-toc "true" "false")))

;; Geekdoc's page templates with one addition, the table of contents
;; above the text.  Geekdoc has no hook there, so the templates are
;; overridden; outside the marked block both are Geekdoc 4.1's own
;; layouts/_default/single.html and list.html, to be compared with the
;; theme's after an upgrade.  Written into the site's layouts/ on every
;; run, like hugo.toml.
(defconst my/repo-docs--toc-block
  "    {{- /* Added by 47-repo-docs.el: table of contents. */ -}}
    {{ if and site.Params.repoDocsToC (findRE `<li>` .TableOfContents 1) }}
      <div class=\"gdoc-toc gdoc-toc__level--{{ default 6 site.Params.geekdocToC }}\">
        {{ .TableOfContents }}
        <hr />
      </div>
    {{ end }}
"
  "Template block inserted before the content of a page.")

(defun my/repo-docs--layout (metadata)
  "Return a Geekdoc page template with the table of contents.
METADATA is the template line that prints the page metadata, the only
line in which Geekdoc's single.html and list.html differ."
  (concat "{{ define \"main\" }}
  {{ partial \"page-header\" . }}


  <article
    class=\"gdoc-markdown gdoc-markdown__align--{{ default \"left\" (.Page.Params.geekdocAlign | lower) }}\"
    id=\"main-content\" tabindex=\"-1\"
  >
    <h1>{{ partial \"utils/title\" . }}</h1>
    " metadata "
" my/repo-docs--toc-block
"    {{ partial \"utils/content\" . }}
  </article>
{{ end }}
"))

(defun my/repo-docs--layouts ()
  "Return the generated layout files as (RELATIVE-PATH . TEXT)."
  (list (cons "layouts/_default/single.html"
              (my/repo-docs--layout "{{ partial \"page-metadata\" . }}"))
        (cons "layouts/_default/list.html"
              (my/repo-docs--layout
               "{{ if ne .Kind \"home\" }}{{ partial \"page-metadata\" . }}{{ end }}"))))

(defun my/repo-docs--write-if-changed (file text)
  "Write TEXT to FILE unless it already holds exactly that.  Return t if written."
  (unless (and (file-exists-p file)
               (equal text (with-temp-buffer
                             (insert-file-contents file)
                             (buffer-string))))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region text nil file nil 'silent))
    t))

(defun my/repo-docs--prune (content keep)
  "Delete files under CONTENT not in KEEP, then empty directories.
KEEP is a hash table of absolute file names.  Return the number of
files deleted."
  (let ((deleted 0))
    (dolist (file (directory-files-recursively content "" nil))
      (unless (gethash file keep)
        (delete-file file)
        (setq deleted (1+ deleted))))
    (dolist (dir (sort (directory-files-recursively content "" t
                                                    #'file-directory-p)
                       (lambda (a b) (> (length a) (length b)))))
      (when (and (file-directory-p dir)
                 (null (directory-files dir nil
                                        directory-files-no-dot-files-regexp)))
        (delete-directory dir)))
    deleted))

(defvar my/repo-docs--last-report nil
  "Plist describing the last regeneration, for `my/repo-docs-report'.")

(defun my/repo-docs-generate ()
  "Regenerate the site's content and configuration from the repository.
Return a plist (:pages N :written N :deleted N :unresolved LIST
:collisions LIST).  Refuses, changing nothing, when two files would
produce the same page."
  (let* ((files (my/repo-docs--files))
         (map (my/repo-docs--map files))
         (collisions (my/repo-docs--collisions map)))
    (when collisions
      (setq my/repo-docs--last-report (list :collisions collisions))
      (user-error "Files differing only in case, site not regenerated: %s"
                  (mapconcat (lambda (c) (string-join c " / ")) collisions "; ")))
    (let* ((site (my/repo-docs--site))
           (content (my/repo-docs--content-dir))
           (weights (my/repo-docs--weights map))
           (unresolved (list 'unresolved))
           (keep (make-hash-table :test #'equal))
           (seen (make-hash-table :test #'equal))
           (written 0)
           (pages 0))
      (make-directory content t)
      (when (my/repo-docs--write-if-changed (expand-file-name "hugo.toml" site)
                                            (my/repo-docs--hugo-config))
        (setq written (1+ written)))
      (dolist (layout (my/repo-docs--layouts))
        (when (my/repo-docs--write-if-changed
               (expand-file-name (car layout) site) (cdr layout))
          (setq written (1+ written))))
      (maphash
       (lambda (key entry)
         ;; A README and its folder share one entry; write it once.
         (let ((target (expand-file-name (plist-get entry :content) content)))
           (unless (gethash target seen)
             (puthash target t seen)
             (puthash target t keep)
             (setq pages (1+ pages))
             (let ((owner (if (and (plist-get entry :section)
                                   (my/repo-docs--markdown-p key))
                              (my/repo-docs--dir-of key)
                            key)))
               (when (my/repo-docs--write-if-changed
                      target
                      (my/repo-docs--page-text owner entry map weights
                                               unresolved))
                 (setq written (1+ written)))))))
       map)
      (let ((report (list :pages pages
                          :written written
                          :deleted (my/repo-docs--prune content keep)
                          :unresolved (nreverse (cdr unresolved))
                          :collisions nil)))
        (setq my/repo-docs--last-report report)
        report))))

;; ============================================================
;; THEME AND SERVER
;; ============================================================

(defun my/repo-docs--theme-dir ()
  "Return the theme directory inside the site."
  (expand-file-name (concat "themes/" my/repo-docs--theme-name "/")
                    (my/repo-docs--site)))

(defun my/repo-docs--ensure-theme ()
  "Install Geekdoc from its release bundle when the site lacks it.
Blocks while downloading (about 6 MB, once per machine)."
  (let ((dir (my/repo-docs--theme-dir)))
    (unless (file-exists-p (expand-file-name "theme.toml" dir))
      (unless (executable-find "tar")
        (user-error "tar not found; needed to unpack the Geekdoc theme"))
      (let ((archive (make-temp-file "hugo-geekdoc" nil ".tar.gz")))
        (unwind-protect
            (progn
              (message "Downloading the Geekdoc theme...")
              (url-copy-file my/repo-docs-theme-url archive t)
              (make-directory dir t)
              (unless (eq 0 (call-process "tar" nil nil nil
                                          "-xzf" archive "-C" dir))
                (delete-directory dir t)
                (user-error "Could not unpack %s" my/repo-docs-theme-url))
              (message "Geekdoc installed in %s" dir))
          (delete-file archive))))))

(defun my/repo-docs--serving-p ()
  "Non-nil when the preview server runs."
  (let ((proc (get-buffer-process my/repo-docs--server-buffer)))
    (and proc (process-live-p proc))))

(defun my/repo-docs--serve ()
  "Start `hugo server' for the site unless it runs.  Return non-nil if started."
  (unless (my/repo-docs--serving-p)
    (unless (executable-find my/repo-docs-hugo-program)
      (user-error "%s not found; install Hugo 0.160 or newer"
                  my/repo-docs-hugo-program))
    (make-process
     :name "repo-docs-server"
     :buffer (get-buffer-create my/repo-docs--server-buffer)
     :command (list my/repo-docs-hugo-program "server"
                    "--source" (my/repo-docs--site)
                    "--port" (number-to-string my/repo-docs-port))
     :noquery t)
    t))

(defun my/repo-docs--url-for-file (file)
  "Return the preview URL of the page made from FILE, or nil.
FILE is an absolute path; nil when it is not a Markdown file of the
repository."
  (let ((repo (my/repo-docs--repo)))
    (when (and file
               (my/repo-docs--markdown-p file)
               (file-in-directory-p file repo))
      (let* ((rel (file-relative-name file repo))
             (path (if (my/repo-docs--readme-p rel)
                       (my/repo-docs--url-of-dir (my/repo-docs--dir-of rel))
                     (concat "/" (downcase (file-name-sans-extension rel)) "/"))))
        (format "http://localhost:%d%s" my/repo-docs-port path)))))

(defun my/repo-docs--summary (report)
  "Return a one-line summary of REPORT."
  (format "Repo docs: %d pages, %d files written, %d removed%s"
          (plist-get report :pages)
          (plist-get report :written)
          (plist-get report :deleted)
          (let ((n (length (plist-get report :unresolved))))
            (if (zerop n) ""
              (format ", %d unresolved link%s (C-c n x r l)"
                      n (if (= n 1) "" "s"))))))

;; ============================================================
;; COMMANDS
;; ============================================================

;;;###autoload
(defun my/repo-docs-find ()
  "Open a Markdown file of the repository, chosen by path.
Candidates are the paths, so seven README.md files stay seven different
choices; the first H1 of each is shown beside it."
  (interactive)
  (let* ((repo (my/repo-docs--repo))
         (files (my/repo-docs--files))
         (titles (make-hash-table :test #'equal)))
    (dolist (rel files)
      (with-temp-buffer
        (insert-file-contents (expand-file-name rel repo) nil 0 4096)
        (goto-char (point-min))
        (when (re-search-forward my/repo-docs--h1-regexp nil t)
          (puthash rel (match-string 1) titles))))
    (let* ((completion-extra-properties
            (list :annotation-function
                  (lambda (rel)
                    (when-let* ((title (gethash rel titles)))
                      (concat "  " (propertize title 'face
                                               'completions-annotations))))))
           (choice (completing-read "Document: " files nil t)))
      (find-file (expand-file-name choice repo)))))

;;;###autoload
(defun my/repo-docs-regenerate ()
  "Regenerate the site from the repository and report."
  (interactive)
  (message "%s" (my/repo-docs--summary (my/repo-docs-generate))))

;;;###autoload
(defun my/repo-docs-preview ()
  "Regenerate the site, serve it and open it in the browser.
Opens the page of the current buffer's file when it is a Markdown file
of the repository, the home page otherwise.  The theme is installed on
first use."
  (interactive)
  (let ((report (my/repo-docs-generate)))
    (my/repo-docs--ensure-theme)
    (let ((started (my/repo-docs--serve))
          (url (or (my/repo-docs--url-for-file buffer-file-name)
                   (format "http://localhost:%d/" my/repo-docs-port))))
      ;; The first build takes a moment; opening at once shows a
      ;; connection error instead.
      (if started
          (run-at-time 2 nil #'browse-url url)
        (browse-url url))
      (message "%s" (my/repo-docs--summary report)))))

;;;###autoload
(defun my/repo-docs-stop ()
  "Stop the preview server."
  (interactive)
  (if (my/repo-docs--serving-p)
      (progn (delete-process (get-buffer-process my/repo-docs--server-buffer))
             (message "Repo docs server stopped"))
    (message "Repo docs server is not running")))

;;;###autoload
(defun my/repo-docs-open-site ()
  "Open the generated site's folder in Dired."
  (interactive)
  (dired (my/repo-docs--site)))

;;;###autoload
(defun my/repo-docs-report ()
  "Show the report of the last regeneration, with unresolved links."
  (interactive)
  (let ((report my/repo-docs--last-report))
    (with-current-buffer (get-buffer-create my/repo-docs-report-buffer)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (cond
         ((null report)
          (insert "No regeneration in this session yet.\n"))
         ((plist-get report :collisions)
          (insert "Not regenerated: files differing only in letter case\n\n")
          (dolist (c (plist-get report :collisions))
            (insert "  " (string-join c "  /  ") "\n")))
         (t
          (insert (my/repo-docs--summary report) "\n\n")
          (if (plist-get report :unresolved)
              (progn
                (insert "Links to .md files the site has no page for:\n\n")
                (dolist (u (plist-get report :unresolved))
                  (insert (format "  %s  ->  %s\n" (car u) (cdr u)))))
            (insert "Every link to a .md file was resolved.\n")))))
      (special-mode)
      (goto-char (point-min)))
    (pop-to-buffer my/repo-docs-report-buffer)))

(defun my/repo-docs--after-save ()
  "Regenerate the site after a Markdown file of the repository is saved.
Only while the preview server runs: otherwise nobody is looking, and
`my/repo-docs-preview' regenerates anyway."
  (when (and my/repo-docs-regenerate-on-save
             (my/repo-docs--serving-p)
             (my/repo-docs--url-for-file buffer-file-name))
    (condition-case err
        (let ((report (my/repo-docs-generate)))
          (when (> (plist-get report :written) 0)
            (message "%s" (my/repo-docs--summary report))))
      (error (message "Repo docs: %s" (error-message-string err))))))

(add-hook 'after-save-hook #'my/repo-docs--after-save)

;; ============================================================
;; MENU (C-c n x r)
;; ============================================================

(transient-define-prefix my/repo-docs-menu ()
  "Markdown documentation of the repository as a Hugo site."
  [["Documents"
    ("f" "Find a document"      my/repo-docs-find)
    ("g" "Regenerate the site"  my/repo-docs-regenerate)
    ("o" "Site folder"          my/repo-docs-open-site)]
   ["Preview"
    ("v" "Preview in browser"   my/repo-docs-preview)
    ("s" "Stop the preview"     my/repo-docs-stop)
    ("l" "Last report"          my/repo-docs-report)]
   [("q" "Quit" transient-quit-one)]])

;; Appended to the Export menu of 12-transient.el through its degrading
;; wrapper, so the menu is intact whether or not this module is loaded.
(when (fboundp 'my/transient-append)
  (my/transient-append 'my/notes-export-menu "Q"
                       '("r" "Repo docs (Hugo) →" my/repo-docs-menu)))

(provide 'repo-docs)

;;; 47-repo-docs.el ends here
