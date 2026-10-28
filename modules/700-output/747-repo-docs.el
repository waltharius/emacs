;;; 747-repo-docs.el --- Documentation of git repositories as one Hugo site -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Default: off
;; MyPKS-Switch: my/repo-docs-mode

;;; Commentary:
;; The documentation files of several git repositories -- by default the
;; NixOS configuration in ~/nixos and this configuration in ~/.emacs.d --
;; served as one read-only Hugo site with the Geekdoc theme
;; (https://github.com/thegeeklab/hugo-geekdoc).  Each repository is a
;; section of its own, named after it (/nixos/, /emacs/), laid out by the
;; repository's own folders, its root files listed in the section.  The
;; files are edited where they are, in the repository, and committed
;; there by hand; the site is only a way of reading them.
;;
;; Which repositories, and which of their files, is set per machine in
;; `my/repo-docs-repositories' (Customize saves it in the machine's own
;; settings): a name, a folder, and git pathspecs of the files to take
;; and to leave out.  A repository missing on a machine is left out and
;; named in the report.  Markdown and plain-text files are shown.
;;
;; WHY NOT A DENOTE SILO
;; ---------------------
;; A silo is a directory under ~/notes/: synced by Syncthing,
;; auto-committed on idle by 207-git.el, and full of Denote file names
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
;; repositories and owned by this module (anything else in it is
;; deleted).  Paths below are the site's: the repository's name, then
;; its path, e.g. nixos/docs/BACKUPS.md.
;;   - the home page lists the repositories; each repository's root is
;;     a section titled with its `:title' (its name by default);
;;   - a README (.md or .txt) becomes the page of its FOLDER
;;     (_index.md), titled with the folder name and a trailing slash,
;;     e.g. "devices/"; so does a file named like a folder beside it
;;     when the folder has no README (CHANGELOG.md for changelog/) --
;;     otherwise both would get one URL; the file's own H1 stays in
;;     the text as an H2 under it, unless it only repeats the folder
;;     name; two such files for one folder stop the run;
;;   - a folder without a README still appears, titled the same way, with
;;     Geekdoc's `toc-tree' listing what is inside;
;;   - every other file becomes a page titled with its first H1, which is
;;     taken out of the text; a file without an H1, and every plain-text
;;     file, is titled with its name; plain text is shown as it is, in a
;;     preformatted block;
;;   - in each folder, subfolders come first, then files in file-name
;;     order (the guide's 01-..08- prefixes give the reading order);
;;   - relative links to .md files and to folders are rewritten to the
;;     URL of the page they become, anchors kept; links Hugo would not
;;     find, or leading out of the repository, are left as written and
;;     listed in the report.
;; Above the text of every page with headings sits its table of
;; contents (`my/repo-docs-toc'), from Geekdoc's templates overridden in
;; the site's layouts/ -- Geekdoc has no hook there.
;;
;; URLs are the site path in lower case: docs/BACKUPS.md of nixos is read
;; at /nixos/docs/backups/.  They are written into each page's `url', so a link
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
;; SWITCH
;; ------
;; `my/repo-docs-mode': on, the regeneration on save and the entry in the
;; Export menu; off, neither, and the preview server is stopped.  The
;; commands stay for M-x.
;;
;; THEME
;; -----
;; Geekdoc is installed from its release bundle, not cloned: the
;; repository holds sources that need an npm build, the bundle holds the
;; built assets (Geekdoc's own "Getting started").  The bundle is fetched
;; with `url-copy-file' when themes/hugo-geekdoc is missing, checked
;; against `my/repo-docs-theme-sha256' (`my/check-sha256', 000-core.el),
;; unpacked with tar into a fresh folder beside the theme's, and renamed
;; into place only when tar succeeded.  The URL names one release, not
;; latest/: updating the theme is a deliberate change of the URL and its
;; digest, never something a download does by itself.  Geekdoc 4.x needs
;; Hugo 0.160 or newer.
;;
;; ADDRESSES AND PUBLISHING
;; ------------------------
;; Three settings, each optional: `my/repo-docs-lan-host' lets the
;; preview server listen on the local network under this machine's
;; name; `my/repo-docs-url' is the address of the site on a server (a
;; machine at home or on the internet), where `w' opens pages; and
;; `my/repo-docs-remote' is where `p' uploads the built site, mirrored
;; with rsync --delete after a question that names the server and says
;; the folder becomes an exact copy -- a home folder or the root is
;; refused, as for the blog (SAFETY.org 1.5).  Hugo and rsync run with
;; argument lists, rsync only after Hugo succeeded.
;;
;; MENU (C-c n x r)
;; ----------------
;;   f  find a document       v  preview in the browser   w  open on the server
;;   g  regenerate the site   s  stop the preview         p  publish
;;   o  site folder           l  last report
;;
;; Docs: ~/.emacs.d/function_helper.org::#repo-docs

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'url-util)
(require 'json)
(require 'transient)
;; Required, not declared: since Org 9.7 (Emacs 30) org-element-property
;; and org-element-type live in org-element-ast.el, the first made by
;; define-inline, which check-declare cannot see; a declaration naming
;; either file fails on one version of Org.  Org is loaded at start-up
;; by other modules, so the require costs nothing.
(require 'org-element)

;; ============================================================
;; SETTINGS
;; ============================================================

(defgroup my/repo-docs nil
  "Markdown documentation of a git repository as a Hugo site."
  :tag "Repository docs site"
  :group 'mypks-publishing)

(defcustom my/repo-docs-repositories
  '(("nixos" :directory "~/nixos/")
    ("emacs" :directory "~/.emacs.d/" :exclude ("hugo/" "tests/")))
  "Git repositories whose documentation the site shows, in this order.
Each entry is (NAME . PROPERTIES):
  NAME        the section of the repository: its folder in the site and
              the first part of its URLs (/NAME/...); lower-case
              letters, digits and hyphens
  :directory  the repository, a git working tree
  :title      title of the section; NAME when absent
  :include    git pathspecs of the files taken (\"*.md\" matches at
              any depth); `my/repo-docs-default-include' when absent
  :exclude    git pathspecs of files left out, e.g. \"hugo/\" for a
              folder
Letter case does not matter in the pathspecs.  Only Markdown, plain-text
and Org files are shown, whatever the pathspecs take; Org files only
when ox-hugo is installed.  A repository
missing on this machine is left out and named in the report.  Saved in
this machine's settings, so each machine can list its own."
  :type '(repeat
          (cons :tag "Repository"
                (string :tag "Name")
                (plist :tag "Properties"
                       :options ((:directory directory)
                                 (:title string)
                                 (:include (repeat string))
                                 (:exclude (repeat string))))))
  :group 'my/repo-docs)

(defcustom my/repo-docs-default-include '("*.md" "*.txt" "*.org")
  "Git pathspecs of the files taken from a repository without `:include'."
  :type '(repeat string)
  :group 'my/repo-docs)

(defcustom my/repo-docs-site-directory "~/projects/nixos-docs-site/"
  "Hugo site generated from `my/repo-docs-repositories'.
Created when missing.  Everything in it is generated or downloaded, so
it is kept outside the notes tree and outside any repository."
  :type 'directory
  :group 'my/repo-docs)

(defcustom my/repo-docs-title "Repositories"
  "Title of the site, shown in its header and on its home page."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-port 1316
  "Port of `hugo server'.
1313-1315 are taken by the sites of 746-blog.el."
  :type 'integer
  :group 'my/repo-docs)

(defcustom my/repo-docs-lan-host nil
  "Name or address of this machine in the local network, or nil.
Nil: the preview server listens on this machine only.  A name such as
\"laptop.lan\" or an address such as \"192.0.2.20\": it listens
on every network interface, its pages addressed as
http://HOST:PORT/, so other machines of the network can read the site
-- anyone in that network, as far as this machine's firewall lets
them."
  :type '(choice (const :tag "This machine only" nil)
                 (string :tag "Name or address in the network"))
  :group 'my/repo-docs)

(defcustom my/repo-docs-url nil
  "Address the site is read at on a server, or nil.
A server in the local network or on the internet, e.g.
\"https://docs.example.org/\".  `my/repo-docs-open-on-server' opens
pages there, and the build `my/repo-docs-publish' uploads takes it as
its base address."
  :type '(choice (const :tag "None" nil) (string :tag "Address"))
  :group 'my/repo-docs)

(defcustom my/repo-docs-remote nil
  "Where `my/repo-docs-publish' uploads the built site, or nil.
An rsync destination such as \"user@server:/var/www/docs/\" (the
trailing slash matters).  The folder there becomes an exact copy of the
build: anything else in it is deleted.  A home folder or the root is
refused (`my/upload-destination-problem').  Nil: the site is not
published."
  :type '(choice (const :tag "Not published" nil) (string :tag "rsync destination"))
  :group 'my/repo-docs)

(defcustom my/repo-docs-rsync-program "rsync"
  "rsync executable, for `my/repo-docs-publish'."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-hugo-program "hugo"
  "Hugo executable."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-theme-url
  "https://github.com/thegeeklab/hugo-geekdoc/releases/download/v4.1.4/hugo-geekdoc.tar.gz"
  "Release bundle of the Geekdoc theme, unpacked into themes/hugo-geekdoc.
One release, so that the theme changes only when this value does.  To
update: the new release's URL here and its digest in
`my/repo-docs-theme-sha256', then delete themes/hugo-geekdoc in the site."
  :type 'string
  :group 'my/repo-docs)

(defcustom my/repo-docs-theme-sha256
  "384675981b41bf70fbc2943d05fadb20ac6090f52c08550fd139842bdb8cb260"
  "SHA-256 of the bundle at `my/repo-docs-theme-url', or nil not to check.
A download with another digest is not unpacked.  `sha256sum' on a copy
downloaded by hand gives the value for a new release."
  :type '(choice (const :tag "Do not check" nil) string)
  :group 'my/repo-docs)

(defcustom my/repo-docs-toc t
  "Non-nil shows a table of contents above the text of each page.
Only pages with headings below the title get one."
  :type 'boolean
  :group 'my/repo-docs)

(defcustom my/repo-docs-regenerate-on-save t
  "Non-nil regenerates the site when a document of a repository is
saved while the preview server runs."
  :type 'boolean
  :group 'my/repo-docs)

(defconst my/repo-docs-report-buffer "*Repo docs*"
  "Buffer holding the report of the last regeneration.")

(defconst my/repo-docs--server-buffer "*Repo docs server*"
  "Buffer of the `hugo server' process.")

(defconst my/repo-docs--publish-buffer "*Repo docs publish*"
  "Buffer of the build and upload of `my/repo-docs-publish'.")

(defconst my/repo-docs--theme-name "hugo-geekdoc"
  "Directory name of the theme under themes/.")

;; ============================================================
;; PATHS
;; ============================================================
;; Pages are addressed by their SITE PATH: the repository's name, then
;; the path in the repository -- nixos/docs/BACKUPS.md.  The site's root
;; is "", a repository's root its name.

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

(defun my/repo-docs--text-p (path)
  "Non-nil when PATH names a plain-text file."
  (let ((case-fold-search t))
    (string-match-p "\\.txt\\'" path)))

(defun my/repo-docs--document-p (path)
  "Non-nil when PATH names a file the site shows: Markdown or plain text."
  (or (my/repo-docs--markdown-p path) (my/repo-docs--text-p path)))

(defun my/repo-docs--readme-p (rel)
  "Non-nil when path REL is a README the site shows."
  (and (my/repo-docs--known-document-p rel)
       (string-equal-ignore-case
        (file-name-sans-extension (file-name-nondirectory rel)) "README")))

(defun my/repo-docs--dir-of (rel)
  "Return the directory part of REL without a trailing slash, \"\" at the root."
  (directory-file-name (or (file-name-directory rel) "")))

(defun my/repo-docs--repo-dir (repo)
  "Return the directory of REPO, an entry of `my/repo-docs-repositories'."
  (file-name-as-directory (expand-file-name (plist-get (cdr repo) :directory))))

(defun my/repo-docs--repo-title (repo)
  "Return the title of REPO's section."
  (or (plist-get (cdr repo) :title) (car repo)))

(defun my/repo-docs--check-repositories ()
  "Stop with a readable message when `my/repo-docs-repositories' is wrong."
  (unless my/repo-docs-repositories
    (user-error "No repositories in `my/repo-docs-repositories'"))
  (let ((seen '()))
    (dolist (repo my/repo-docs-repositories)
      (let ((name (car-safe repo)))
        (unless (and (stringp name)
                     (let ((case-fold-search nil))
                       (string-match-p "\\`[a-z0-9][a-z0-9-]*\\'" name)))
          (user-error "Repository name %S: lower-case letters, digits and hyphens only"
                      name))
        (when (member name seen)
          (user-error "Two repositories called %s in `my/repo-docs-repositories'" name))
        (push name seen)
        (unless (stringp (plist-get (cdr repo) :directory))
          (user-error "Repository %s has no :directory" name))))))

(defun my/repo-docs--repo-files (repo &optional org)
  "Return the documents of REPO, relative to it, as git sees them.

The files git would commit -- tracked, plus untracked but not ignored,
so that a new document shows up before its first `git add' -- taken by
the `:include' pathspecs and not left out by the `:exclude' ones, of
the kinds the site shows -- Org files only when ORG is non-nil.
Signals a `user-error' when git fails."
  (let* ((dir (my/repo-docs--repo-dir repo))
         (props (cdr repo))
         (pathspecs (append (or (plist-get props :include) my/repo-docs-default-include)
                            (mapcar (lambda (p) (concat ":(exclude)" p))
                                    (plist-get props :exclude)))))
    (with-temp-buffer
      (let* ((default-directory dir)
             (status (apply #'process-file "git" nil t nil
                            "--icase-pathspecs"
                            "-c" "core.quotePath=false"
                            "ls-files" "-z" "--cached" "--others"
                            "--exclude-standard" "--" pathspecs)))
        (unless (eq status 0)
          (user-error "git ls-files failed in %s: %s"
                      dir (string-trim (buffer-string))))
        (sort (seq-filter
               (lambda (rel)
                 (and (or (my/repo-docs--document-p rel)
                          (and org (my/repo-docs--org-p rel)))
                      (file-regular-p (expand-file-name rel dir))))
               (delete-dups (split-string (buffer-string) "\0" t)))
              #'string<)))))

(defun my/repo-docs--files ()
  "Return the documents of every repository on this machine.
A plist: :files is a list of (SITE-PATH . ABSOLUTE-PATH), sorted by
site path; :missing the names of the repositories whose folder this
machine lacks; :no-org non-nil when ox-hugo is missing, so that Org
files were left out.  Stops when none is there: an empty site would look
like deleted documentation."
  (my/repo-docs--check-repositories)
  (let ((files '())
        (missing '())
        (org (my/repo-docs--ox-hugo-p)))
    (dolist (repo my/repo-docs-repositories)
      (let ((dir (my/repo-docs--repo-dir repo)))
        (if (not (file-directory-p dir))
            (push (car repo) missing)
          (dolist (rel (my/repo-docs--repo-files repo org))
            (push (cons (concat (car repo) "/" rel) (expand-file-name rel dir))
                  files)))))
    (when (= (length missing) (length my/repo-docs-repositories))
      (user-error "No repository of `my/repo-docs-repositories' is on this machine: %s"
                  (string-join (nreverse missing) ", ")))
    (list :files (sort files (lambda (a b) (string< (car a) (car b))))
          :missing (nreverse missing)
          :no-org (not org))))

(defun my/repo-docs--site-path-of (file)
  "Return the site path of FILE, an absolute path, or nil.
Nil when FILE is no document in a repository of
`my/repo-docs-repositories'; whether its pathspecs take it is not
checked."
  (when (and file (my/repo-docs--known-document-p file))
    (let ((path (expand-file-name file)))
      (seq-some (lambda (repo)
                  (let ((dir (my/repo-docs--repo-dir repo)))
                    (when (string-prefix-p dir path)
                      (concat (car repo) "/" (substring path (length dir))))))
                my/repo-docs-repositories))))

;; ============================================================
;; PAGE MAP: site path -> content file and URL
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

(defun my/repo-docs--folder-pages (files sections)
  "Return folder -> the files of FILES claiming to be its page.
A README claims its own folder; a file named like a folder beside it
(CHANGELOG.md beside changelog/) claims that folder, so that the two do
not get one URL.  SECTIONS are the folders, as `my/repo-docs--sections'
returns them.  More than one claim for a folder is a collision."
  (let ((by-name (make-hash-table :test #'equal))
        (claims (make-hash-table :test #'equal)))
    (dolist (dir sections)
      (puthash (downcase dir) dir by-name))
    (dolist (rel files)
      (let ((dir (if (my/repo-docs--readme-p rel)
                     (my/repo-docs--dir-of rel)
                   (gethash (downcase (file-name-sans-extension rel)) by-name))))
        (when dir
          (push rel (gethash dir claims)))))
    claims))

(defun my/repo-docs--map (files)
  "Return a hash table describing the pages made from FILES.
FILES is a list of (SITE-PATH . ABSOLUTE-PATH).

Keys are site paths of files and of folders (without trailing slash,
\"\" for the root).  Each value is a plist:
  :content  content-relative path of the generated file
  :url      URL of the page
  :file     site path of the source file, or nil for a folder without
            a page of its own
  :source   absolute path of the source file, or nil
  :section  non-nil for a folder page
  :dir      for a folder page, the folder's key
A folder whose page comes from a file has two keys, the folder's and
the file's, both leading to one entry."
  (let* ((rels (mapcar #'car files))
         (sections (my/repo-docs--sections rels))
         (claims (my/repo-docs--folder-pages rels sections))
         (map (make-hash-table :test #'equal)))
    (dolist (dir sections)
      (let ((owner (car (gethash dir claims))))
        (puthash dir
                 (list :content (if (string-empty-p dir)
                                    "_index.md"
                                  (concat (downcase dir) "/_index.md"))
                       :url (my/repo-docs--url-of-dir dir)
                       :file owner
                       :source (and owner (cdr (assoc owner files)))
                       :section t
                       :dir dir)
                 map)))
    (let ((owner-of (make-hash-table :test #'equal)))
      (maphash (lambda (dir rels) (dolist (rel rels) (puthash rel dir owner-of))) claims)
      (setq claims owner-of))
    (dolist (file files)
      (let* ((rel (car file))
             (owned (gethash rel claims)))
        (if owned
            ;; The folder's page: a link to the folder and a link to the
            ;; file land on the same page.
            (puthash rel (gethash owned map) map)
          (let ((stem (downcase (file-name-sans-extension rel))))
            (puthash rel
                     (list :content (concat stem ".md")
                           :url (concat "/" stem "/")
                           :file rel
                           :source (cdr file)
                           :section nil)
                     map)))))
    map))

(defun my/repo-docs--collisions (map)
  "Return lists of site paths that MAP sends to one page.
Two files differing only in letter case collide, since URLs are lower
case; so do two files of one name and different kinds (notes.md and
notes.txt), and two files claiming one folder (README.md and
README.txt)."
  (let ((by-content (make-hash-table :test #'equal))
        collisions)
    (maphash (lambda (key entry)
               (when (and (plist-get entry :file)
                          (not (and (plist-get entry :section)
                                    (equal key (plist-get entry :dir)))))
                 (push key (gethash (plist-get entry :content) by-content))))
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
folder of SOURCE-REL, a site path; a target outside SOURCE-REL's
repository, or one MAP does not know, also gives nil.  The anchor, if
any, is kept."
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
           (repo (substring source-rel 0 (string-search "/" source-rel)))
           (rel (and (string-prefix-p (concat root repo "/") abs)
                     (directory-file-name (substring abs (length root)))))
           (entry (and rel (gethash rel map))))
      (when entry
        (concat (plist-get entry :url) anchor)))))

(defun my/repo-docs--rewrite-links (line source-rel map unresolved)
  "Return LINE with relative links rewritten for SOURCE-REL using MAP.

Inline links `](target)' and reference definitions `[id]: target' are
rewritten.  A relative target that names a document (.md, .txt) and
cannot be resolved is pushed onto the list in the cdr of UNRESOLVED
as (SOURCE-REL . TARGET)."
  (let ((rewrite
         (lambda (target)
           (or (my/repo-docs--resolve target source-rel map)
               (progn
                 (when (and (not (string-match-p
                                  "\\`\\([a-zA-Z][a-zA-Z0-9+.-]*:\\|#\\|/\\)"
                                  target))
                            (my/repo-docs--known-document-p
                             (car (split-string target "#"))))
                   (push (cons source-rel target) (cdr unresolved)))
                 target)))))
    (setq line
          (replace-regexp-in-string
           "](\\([^)[:space:]]+\\)\\([ \t]+\"[^\"]*\"\\)?)"
           (lambda (match)
             ;; `replace-regexp-in-string' reads the match data after
             ;; this returns; the rewrite must not change it.
             (save-match-data
               (concat "](" (funcall rewrite (match-string 1 match))
                       (or (match-string 2 match) "") ")")))
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
;; ORG FILES: through ox-hugo
;; ============================================================
;; An Org file is exported to Markdown by ox-hugo, the exporter 746-blog
;; uses, through a backend derived from it that differs in one thing:
;; links to files.  A link to another document of the site leads to its
;; page (with the heading or custom id it names); a link to a document
;; the site lacks becomes its description, reported; a `denote:' link
;; -- a note, which is no document of a repository -- becomes its
;; description; anything else (images, other files) is ox-hugo's, which
;; copies the file into the site's static/.  The front matter ox-hugo
;; writes is replaced by the module's own.  Shortcodes written in the
;; file are escaped before the export, and the page is checked once
;; more after it: every shortcode the page still calls that is not one
;; of `my/repo-docs--own-shortcodes' (an image's figure, which ox-hugo
;; writes, and the module's toc-tree) is escaped then.  One unknown
;; page in a relref fails Hugo's whole build, and the escape before the
;; export did not reach a page on 2026-10-28 (the owner's docs site:
;; `hugo server' exited on function_helper.org's own example of a
;; relref), so the page itself is the last word.  An export is cached for the
;; session by the file's modification time, size and the set of pages:
;; function_helper.org takes seconds, and the site is regenerated on
;; every save while the preview runs.

(defvar org-hugo-base-dir)
(defvar org-export-filter-parse-tree-functions)
(declare-function org-hugo-link "ext:ox-hugo" (link desc info))
(declare-function org-hugo-slug "ext:ox-hugo" (str &optional allow-double-hyphens))
(declare-function org-export-define-derived-backend "ox")
(declare-function org-export-get-backend "ox" (name))
(declare-function org-export-as "ox")
(declare-function org-find-exact-headline-in-buffer "org")
(declare-function org-entry-get "org")

(defun my/repo-docs--org-p (path)
  "Non-nil when PATH names an Org file."
  (let ((case-fold-search t))
    (string-match-p "\\.org\\'" path)))

(defun my/repo-docs--ox-hugo-p ()
  "Load ox-hugo; non-nil when it is installed."
  (require 'ox-hugo nil t))

(defvar my/repo-docs--org-context nil
  "During the export of an Org file: (SITE-PATH MAP UNRESOLVED).")

(defvar my/repo-docs--org-cache (make-hash-table :test #'equal)
  "Absolute path -> (STAMP REPORTED (TITLE . BODY)) of this session's
Org exports; REPORTED is what the export added to the report.")

(defun my/repo-docs--org-anchor (file search)
  "Return the page anchor for SEARCH, the `::' part of a link to FILE.
\"#id\" is a custom id; \"*Heading\" the heading's custom id when it has
one, otherwise its slug, as ox-hugo makes them.  Nil for anything else,
and for a heading FILE does not have."
  (cond
   ((null search) nil)
   ((string-prefix-p "#" search) search)
   ((and (string-prefix-p "*" search) (my/repo-docs--org-p file) (file-readable-p file))
    (let ((heading (string-trim (substring search 1))))
      (with-temp-buffer
        (insert-file-contents file)
        (delay-mode-hooks (org-mode))
        (let ((marker (org-find-exact-headline-in-buffer heading)))
          (when marker
            (goto-char marker)
            (concat "#" (or (org-entry-get nil "CUSTOM_ID")
                            (org-hugo-slug heading))))))))))

(defun my/repo-docs--org-link (link desc info)
  "Transcode LINK, with description DESC, for a page of the site.
INFO is the export's communication channel.  See the section's
comment for what becomes of which link."
  (let ((type (org-element-property :type link))
        (path (org-element-property :path link)))
    (cond
     ;; Without Denote loaded, Org reads a denote: link as a fuzzy one,
     ;; which the export would mark as broken, identifier and all.
     ((or (equal type "denote")
          (and (equal type "fuzzy") (string-prefix-p "denote:" path)))
      (or desc ""))
     ((and (equal type "file") (my/repo-docs--known-document-p path))
      (pcase-let* ((`(,source ,map ,unresolved) my/repo-docs--org-context)
                   (file (expand-file-name path))
                   (target (my/repo-docs--site-path-of file))
                   (entry (and target
                               ;; Within the repository of the source only.
                               (equal (car (split-string source "/"))
                                      (car (split-string target "/")))
                               (gethash target map))))
        (if entry
            (let ((url (concat (plist-get entry :url)
                               (or (my/repo-docs--org-anchor
                                    file (org-element-property :search-option link))
                                   ""))))
              (format "[%s](%s)" (or desc url) url))
          (push (cons source path) (cdr unresolved))
          (or desc path))))
     (t (org-hugo-link link desc info)))))

(defun my/repo-docs--known-document-p (path)
  "Non-nil when PATH names a file of a kind the site shows."
  (or (my/repo-docs--document-p path) (my/repo-docs--org-p path)))

(defun my/repo-docs--org-backend ()
  "Return the name of the export backend for Org pages, defining it once."
  (unless (org-export-get-backend 'my/repo-docs)
    (org-export-define-derived-backend 'my/repo-docs 'hugo
      :translate-alist '((link . my/repo-docs--org-link))))
  'my/repo-docs)

(defun my/repo-docs--org-title (text)
  "Return the #+title of Org TEXT, or nil."
  (let ((case-fold-search t))
    (when (string-match "^#\\+title:[ \t]*\\(.*?\\)[ \t]*$" text)
      (let ((title (match-string 1 text)))
        (unless (string-empty-p title) title)))))

(defun my/repo-docs--org-export (source text site-path map unresolved)
  "Return (TITLE . BODY): Org TEXT of SOURCE as Markdown for SITE-PATH.
MAP resolves links, UNRESOLVED collects those it cannot; see
`my/repo-docs--org-link'.  An export that fails gives a page saying so,
and the failure is reported."
  (let ((title (my/repo-docs--org-title text)))
    (cons
     title
     (condition-case err
         (let* ((org-hugo-base-dir (my/repo-docs--site))
                ;; ox-hugo copies images into static/ and refuses a file
                ;; with an image when the directory is missing.
                (_ (make-directory (expand-file-name "static" org-hugo-base-dir) t))
                (org-export-with-broken-links 'mark)
                ;; No code of a document runs while it is exported: the
                ;; site is regenerated on every save while the preview
                ;; runs (outside review 2026-10-27).
                (org-export-use-babel nil)
                (org-export-filter-parse-tree-functions
                 (remq 'my/org-export-denote-links-to-text org-export-filter-parse-tree-functions))
                (my/repo-docs--org-context (list site-path map unresolved))
                (inhibit-message t)
                (message-log-max nil)
                (out (with-temp-buffer
                       (insert text)
                       ;; The theme draws the table of contents; a later
                       ;; #+options line overrides an earlier one.
                       (insert "\n#+options: toc:nil\n")
                       (setq default-directory (file-name-directory source))
                       (delay-mode-hooks (org-mode))
                       (org-export-as (my/repo-docs--org-backend)))))
           ;; ox-hugo's own front matter goes; the module writes its own.
           (string-trim
            (replace-regexp-in-string "\\`\\+\\+\\+\n\\(?:.*\n\\)*?\\+\\+\\+\n" "" out)))
       (error
        (push (cons site-path (format "export failed: %s" (error-message-string err)))
              (cdr unresolved))
        (format "Export of %s failed: %s" site-path (error-message-string err)))))))

(defun my/repo-docs--org-page (source site-path map unresolved signature)
  "Return (TITLE . BODY) for the Org file SOURCE, from the cache if it holds.
SITE-PATH, MAP and UNRESOLVED as in `my/repo-docs--org-export';
SIGNATURE stands for the set of pages, on which the links depend.  A
cached export repeats what it reported."
  (let* ((attrs (file-attributes source))
         (stamp (list (file-attribute-modification-time attrs)
                      (file-attribute-size attrs)
                      signature))
         (hit (gethash source my/repo-docs--org-cache)))
    (if (and hit (equal (car hit) stamp))
        (progn
          (dolist (u (reverse (nth 1 hit))) (push u (cdr unresolved)))
          (nth 2 hit))
      (let* ((mine (list 'unresolved))
             (page (with-temp-buffer
                     (insert-file-contents source)
                     (my/repo-docs--org-export
                      source (my/repo-docs--escape-shortcodes (buffer-string))
                      site-path map mine))))
        (puthash source (list stamp (cdr mine) page) my/repo-docs--org-cache)
        (dolist (u (reverse (cdr mine))) (push u (cdr unresolved)))
        page))))

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

(defun my/repo-docs--escape-shortcodes (text)
  "Return TEXT with every Hugo shortcode call escaped, to show as written.
Hugo runs shortcodes anywhere in a page, in code too: a document that
writes about one -- `{{< relref \"x\" >}}' in a change log -- would
fail the build or show its output.  Hugo's escape, {{</* ... */>}},
prints the call as it was written; one already escaped stays so.  The
rule is 000-core.el's, shared with 746-blog.el."
  (my/hugo-escape-shortcodes text))

(defconst my/repo-docs--own-shortcodes '("figure" "toc-tree")
  "Shortcodes a page may call: what ox-hugo writes for an image, and the
theme's folder listing.  Any other call left in a page is escaped by
`my/repo-docs--escape-foreign-shortcodes'.")

(defun my/repo-docs--escape-foreign-shortcodes (text)
  "Return TEXT with every shortcode call escaped except the module's own.
The last check of a page before it is written: whatever came through the
export unescaped -- a relref in documentation about relrefs -- is shown
as written rather than run (see the commentary on Org files).  It does
its own escaping and calls nothing of the step before the export, so it
holds when that step does not: a safety net that shares the code of
what it guards fails with it (found by test-repo-docs on the owner's
machine, 2026-10-28)."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (while (re-search-forward
            "{{\\([<%]\\)\\(/\\*\\)?\\(.*?\\)\\(\\*/\\)?\\([>%]\\)}}" nil t)
      ;; The groups first: `split-string' below matches too, and would
      ;; leave `replace-match' the match data of its own search.
      (let ((open (match-string 1))
            (escaped (match-beginning 2))
            (inner (match-string 3))
            (close (match-string 5))
            (start (match-beginning 0))
            (end (match-end 0)))
        (unless (or escaped
                    (member (car (split-string inner nil t))
                            my/repo-docs--own-shortcodes))
          (delete-region start end)
          (goto-char start)
          (insert "{{" open "/*" inner "*/" close "}}"))))
    (buffer-string)))

(defun my/repo-docs--weights (map)
  "Return a hash table of site path -> weight for the pages in MAP.
The repositories come in the order of `my/repo-docs-repositories'.
Within a folder, subfolders come first, sorted by name, then files in
file-name order.  A file that is a folder's page takes no place among
its siblings."
  (let ((children (make-hash-table :test #'equal))
        (weights (make-hash-table :test #'equal)))
    (maphash
     (lambda (key entry)
       (unless (or (string-empty-p key)
                   ;; A folder and the file that is its page share one
                   ;; entry; only the folder counts as a child.
                   (and (plist-get entry :section)
                        (not (equal key (plist-get entry :dir)))))
         (push key (gethash (my/repo-docs--dir-of key) children))))
     map)
    (maphash
     (lambda (parent keys)
       (let ((sorted (if (string-empty-p parent)
                         (seq-filter (lambda (name) (member name keys))
                                     (mapcar #'car my/repo-docs-repositories))
                       (sort keys
                             (lambda (a b)
                               (let ((sa (plist-get (gethash a map) :section))
                                     (sb (plist-get (gethash b map) :section)))
                                 (if (eq (not sa) (not sb))
                                     (string< (downcase a) (downcase b))
                                   sa))))))
             (weight 0))
         (dolist (key sorted)
           (puthash key (setq weight (+ weight 10)) weights))))
     children)
    weights))

(defun my/repo-docs--plain-text (text)
  "Return (nil . BODY): TEXT, a plain-text file, as a preformatted block.
The fence is longer than any run of backticks in TEXT, so nothing in it
can close the block early."
  (let ((longest 2) (start 0))
    (while (string-match "`+" text start)
      (setq longest (max longest (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    (let ((fence (make-string (1+ longest) ?`)))
      (cons nil (concat fence "text\n" (string-trim-right text) "\n" fence)))))

(defun my/repo-docs--org-section-page (page label)
  "Return PAGE, (TITLE . BODY) of an Org export, for a folder titled LABEL.
Nil LABEL: PAGE as it is.  Otherwise the Org title, unless it only
repeats LABEL, goes into the text as an H2, as a Markdown file's H1
does."
  (if (or (null label) (null (car page))
          (equal (downcase (string-trim (car page) "[`/ \t]*" "[`/ \t]*"))
                 (downcase (string-trim label "[`/ \t]*" "[`/ \t]*"))))
      page
    (cons (car page) (concat "## " (car page) "\n\n" (cdr page)))))

(defun my/repo-docs--label (key)
  "Return the title of the folder page of KEY.
The site's title at the root, the repository's at a repository's root,
the folder name with a trailing slash below."
  (cond ((string-empty-p key) my/repo-docs-title)
        ((not (string-search "/" key))
         (my/repo-docs--repo-title (or (assoc key my/repo-docs-repositories)
                                       (list key))))
        (t (concat (file-name-nondirectory key) "/"))))

(defun my/repo-docs--page-text (key entry map weights unresolved &optional signature)
  "Return the full text of the generated file for KEY and its ENTRY.
SIGNATURE stands for the set of pages, for the cache of Org exports."
  (let* ((file (plist-get entry :file))
         (source (plist-get entry :source))
         (section (plist-get entry :section))
         (label (and section (my/repo-docs--label key)))
         (org (and source (my/repo-docs--org-p file)))
         (text (and source (not org)
                    (with-temp-buffer
                      (insert-file-contents source)
                      (buffer-string))))
         (parsed (cond
                  (org (my/repo-docs--org-section-page
                        (my/repo-docs--org-page source file map unresolved signature)
                        label))
                  ((null text) nil)
                  ((my/repo-docs--text-p file) (my/repo-docs--plain-text text))
                  (t (my/repo-docs--transform text file map unresolved label))))
         (title (cond
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
         ;; An Org page's shortcodes were escaped in its source, a
         ;; Markdown or text page's here; the page is then checked once
         ;; more, and only the module's own shortcodes (an image's
         ;; figure, which ox-hugo added) are left to run.
         (my/repo-docs--escape-foreign-shortcodes
          (if org (cdr parsed) (my/repo-docs--escape-shortcodes (cdr parsed))))
       ;; A folder without a page of its own: let the theme list its
       ;; contents.
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
  "    {{- /* Added by 747-repo-docs.el: table of contents. */ -}}
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

(defvar my/repo-docs--last-map nil
  "The page map of the last regeneration, for finding a file's page.")

(defun my/repo-docs-generate ()
  "Regenerate the site's content and configuration from the repositories.
Return a plist (:pages N :written N :deleted N :unresolved LIST
:collisions LIST :missing NAMES).  Refuses, changing nothing, when two
files would produce the same page."
  (let* ((found (my/repo-docs--files))
         (files (plist-get found :files))
         (map (my/repo-docs--map files))
         (collisions (my/repo-docs--collisions map)))
    (when collisions
      (setq my/repo-docs--last-report (list :collisions collisions))
      (user-error "Files that would make one page, site not regenerated: %s"
                  (mapconcat (lambda (c) (string-join c " / ")) collisions "; ")))
    (let* ((site (my/repo-docs--site))
           (content (my/repo-docs--content-dir))
           (weights (my/repo-docs--weights map))
           (unresolved (list 'unresolved))
           (signature (sxhash-equal (sort (hash-table-keys map) #'string<)))
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
         ;; A folder and the file that is its page share one entry;
         ;; write it once, as the folder's.
         (let ((target (expand-file-name (plist-get entry :content) content)))
           (unless (gethash target seen)
             (puthash target t seen)
             (puthash target t keep)
             (setq pages (1+ pages))
             (let ((owner (if (plist-get entry :section)
                              (plist-get entry :dir)
                            key)))
               (when (my/repo-docs--write-if-changed
                      target
                      (my/repo-docs--page-text owner entry map weights
                                               unresolved signature))
                 (setq written (1+ written)))))))
       map)
      (let ((report (list :pages pages
                          :written written
                          :deleted (my/repo-docs--prune content keep)
                          :unresolved (nreverse (cdr unresolved))
                          :collisions nil
                          :missing (plist-get found :missing)
                          :no-org (plist-get found :no-org))))
        (setq my/repo-docs--last-report report
              my/repo-docs--last-map map)
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
Blocks while downloading (about 6 MB, once per machine).  The bundle
is checked against `my/repo-docs-theme-sha256' and unpacked into a
fresh folder beside the theme's, renamed into place only when tar
succeeded, so a failure never leaves a half-filled theme behind."
  (let ((dir (directory-file-name (my/repo-docs--theme-dir))))
    (unless (file-exists-p (expand-file-name "theme.toml" dir))
      (unless (executable-find "tar")
        (user-error "tar not found; needed to unpack the Geekdoc theme"))
      (let ((archive (make-temp-file "hugo-geekdoc" nil ".tar.gz"))
            (staging nil))
        (unwind-protect
            (progn
              (message "Downloading the Geekdoc theme...")
              (url-copy-file my/repo-docs-theme-url archive t)
              (unless (my/check-sha256 archive my/repo-docs-theme-sha256
                                       "Geekdoc theme")
                (message "Geekdoc theme: no SHA-256 recorded, not checked"))
              (make-directory (file-name-directory dir) t)
              ;; Beside the target, so that the rename stays on one file system.
              (setq staging (make-temp-file
                             (expand-file-name ".installing-" (file-name-directory dir))
                             t))
              (unless (eq 0 (call-process "tar" nil nil nil
                                          "-xzf" archive "-C" staging))
                (user-error "Could not unpack %s" my/repo-docs-theme-url))
              (when (file-exists-p dir)
                ;; A theme folder without theme.toml: an earlier, broken install.
                (delete-directory dir t))
              (rename-file staging dir)
              (setq staging nil)
              (message "Geekdoc installed in %s" dir))
          (delete-file archive)
          (when (and staging (file-directory-p staging))
            (delete-directory staging t)))))))

(defun my/repo-docs--serving-p ()
  "Non-nil when the preview server runs."
  (let ((proc (get-buffer-process my/repo-docs--server-buffer)))
    (and proc (process-live-p proc))))

(defun my/repo-docs--server-command ()
  "Return the command line of `hugo server' for the site.
With `my/repo-docs-lan-host', listening on every interface under that
name; otherwise on this machine only, Hugo's default."
  (append (list my/repo-docs-hugo-program "server"
                "--source" (my/repo-docs--site)
                "--port" (number-to-string my/repo-docs-port))
          ;; Hugo adds the port to the base address itself.
          (when my/repo-docs-lan-host
            (list "--bind" "0.0.0.0"
                  "--baseURL" (format "http://%s/" my/repo-docs-lan-host)))))

(defun my/repo-docs--server-sentinel (process _event)
  "Report a `hugo server' that stopped: its last lines, and where the rest is.
Until 2026-10-28 a server whose first build failed exited unseen, and
the message \"starting on ...\" stood while the browser found nothing."
  (when (memq (process-status process) '(exit signal))
    (my/hugo-server-report-exit process "Repo docs" my/repo-docs--server-buffer)))

(defun my/repo-docs--serve ()
  "Start `hugo server' for the site unless it runs.  Return non-nil if started."
  (unless (my/repo-docs--serving-p)
    (unless (executable-find my/repo-docs-hugo-program)
      (user-error "%s not found; install Hugo 0.160 or newer"
                  my/repo-docs-hugo-program))
    (make-process
     :name "repo-docs-server"
     :buffer (get-buffer-create my/repo-docs--server-buffer)
     :command (my/repo-docs--server-command)
     :noquery t
     :sentinel #'my/repo-docs--server-sentinel)
    (when my/repo-docs-lan-host
      (message "Repo docs: readable in the network at http://%s:%d/"
               my/repo-docs-lan-host my/repo-docs-port))
    t))

(defun my/repo-docs--base-url ()
  "Return the address the site is read at, without a trailing slash."
  (format "http://localhost:%d" my/repo-docs-port))

(defun my/repo-docs--url-for-file (file &optional base)
  "Return the address of the page made from FILE, or nil.
FILE is an absolute path; nil when the last regeneration made no page
from it.  BASE is the site's address without a trailing slash, the
local preview's by default."
  (when-let* ((path (my/repo-docs--site-path-of file))
              (entry (and my/repo-docs--last-map
                          (gethash path my/repo-docs--last-map))))
    (concat (or base (my/repo-docs--base-url)) (plist-get entry :url))))

(defun my/repo-docs--summary (report)
  "Return a one-line summary of REPORT."
  (format "Repo docs: %d pages, %d files written, %d removed%s%s"
          (plist-get report :pages)
          (plist-get report :written)
          (plist-get report :deleted)
          (let ((n (length (plist-get report :unresolved))))
            (if (zerop n) ""
              (format ", %d unresolved link%s (C-c n x r l)"
                      n (if (= n 1) "" "s"))))
          (concat
           (if (plist-get report :missing)
               (format ", not on this machine: %s"
                       (string-join (plist-get report :missing) ", "))
             "")
           (if (plist-get report :no-org)
               ", Org files left out (ox-hugo is not installed)"
             ""))))

;; ============================================================
;; COMMANDS
;; ============================================================

;;;###autoload
(defun my/repo-docs-find ()
  "Open a document of the repositories, chosen by its site path.
Candidates are the paths, repository name first, so seven README.md
files stay seven different choices; the first H1 of each is shown
beside it (an Org file's #+title)."
  (interactive)
  (let* ((files (plist-get (my/repo-docs--files) :files))
         (titles (make-hash-table :test #'equal)))
    (dolist (file files)
      (unless (my/repo-docs--text-p (car file))
        (with-temp-buffer
          (insert-file-contents (cdr file) nil 0 4096)
          (let ((title (if (my/repo-docs--org-p (car file))
                           (my/repo-docs--org-title (buffer-string))
                         (goto-char (point-min))
                         (and (re-search-forward my/repo-docs--h1-regexp nil t)
                              (match-string 1)))))
            (when title (puthash (car file) title titles))))))
    (let* ((completion-extra-properties
            (list :annotation-function
                  (lambda (rel)
                    (when-let* ((title (gethash rel titles)))
                      (concat "  " (propertize title 'face
                                               'completions-annotations))))))
           (choice (completing-read "Document: " (mapcar #'car files) nil t)))
      (find-file (cdr (assoc choice files))))))

;;;###autoload
(defun my/repo-docs-regenerate ()
  "Regenerate the site from the repositories and report."
  (interactive)
  (message "%s" (my/repo-docs--summary (my/repo-docs-generate))))

;;;###autoload
(defun my/repo-docs-preview ()
  "Regenerate the site, serve it and open it in the browser.
Opens the page of the current buffer's file when the site has one, the
home page otherwise.  The theme is installed on first use."
  (interactive)
  (let ((report (my/repo-docs-generate)))
    (my/repo-docs--ensure-theme)
    (let ((started (my/repo-docs--serve))
          (url (or (my/repo-docs--url-for-file buffer-file-name)
                   (concat (my/repo-docs--base-url) "/"))))
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
(defun my/repo-docs-open-on-server ()
  "Open the page of the current buffer's file on `my/repo-docs-url'.
The home page when the site has no page for the file.  The pages are
the last regeneration's; the server shows what was last published."
  (interactive)
  (unless (and (stringp my/repo-docs-url) (not (string-empty-p my/repo-docs-url)))
    (user-error "No server address: set `my/repo-docs-url' (C-c n , ,)"))
  (let ((base (string-remove-suffix "/" my/repo-docs-url)))
    (unless my/repo-docs--last-map
      (ignore-errors (my/repo-docs-generate)))
    (browse-url (or (my/repo-docs--url-for-file buffer-file-name base)
                    (concat base "/")))))

(defun my/repo-docs--refuse-upload (remote)
  "Stop unless REMOTE may receive the site: set, and not a home or root."
  (unless (and (stringp remote) (not (string-empty-p remote)))
    (user-error "No upload destination: set `my/repo-docs-remote' (C-c n , ,)"))
  (when-let* ((problem (my/upload-destination-problem remote)))
    (user-error "Repo docs: refusing to upload to %s -- %s" remote problem)))

(defun my/repo-docs--run (name command then)
  "Run COMMAND, an argument list, as process NAME in the publish buffer.
THEN is called with no argument when it exits with status 0; any other
end shows the buffer and says so."
  (with-current-buffer (get-buffer-create my/repo-docs--publish-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "$ " (mapconcat #'shell-quote-argument command " ") "\n")))
  (make-process
   :name name
   :buffer my/repo-docs--publish-buffer
   :command command
   :noquery t
   :sentinel (lambda (proc _event)
               (when (memq (process-status proc) '(exit signal))
                 (if (zerop (process-exit-status proc))
                     (funcall then)
                   (display-buffer my/repo-docs--publish-buffer)
                   (message "Repo docs: %s FAILED (exit %d) - see %s"
                            name (process-exit-status proc)
                            my/repo-docs--publish-buffer))))))

(defun my/repo-docs--build-and-upload ()
  "Build the site into public/ and mirror it to `my/repo-docs-remote'.
Two programs, each with an argument list: Hugo, then -- only when it
succeeded -- rsync --delete.  The destination is checked again here, at
the last moment, whoever calls this."
  (let* ((remote my/repo-docs-remote)
         (site (my/repo-docs--site))
         (public (file-name-as-directory (expand-file-name "public" site))))
    (my/repo-docs--refuse-upload remote)
    (with-current-buffer (get-buffer-create my/repo-docs--publish-buffer)
      (let ((inhibit-read-only t)) (erase-buffer)))
    (my/repo-docs--run
     "repo-docs-build"
     (list my/repo-docs-hugo-program "--source" site "--destination" public
           "--baseURL" my/repo-docs-url "--gc" "--minify" "--cleanDestinationDir")
     (lambda ()
       (my/repo-docs--run
        "repo-docs-upload"
        ;; `--': a destination starting with - is a path, never an option.
        (list my/repo-docs-rsync-program "-az" "--delete" "--" public remote)
        (lambda () (message "Repo docs published to %s" remote)))))
    (message "Repo docs: building and uploading to %s..." remote)))

;;;###autoload
(defun my/repo-docs-publish ()
  "Regenerate the site, build it and upload it to `my/repo-docs-remote'.
The upload mirrors the build with rsync --delete, so the folder on the
server ends up holding exactly the build.  Asks first, naming the
server; a home folder or the root is refused.  The build's addresses
are `my/repo-docs-url''s."
  (interactive)
  (my/repo-docs--refuse-upload my/repo-docs-remote)
  (unless (and (stringp my/repo-docs-url) (not (string-empty-p my/repo-docs-url)))
    (user-error "No server address: set `my/repo-docs-url', the address the published site is read at"))
  (dolist (program (list my/repo-docs-hugo-program my/repo-docs-rsync-program))
    (unless (executable-find program)
      (user-error "%s not found on PATH" program)))
  (let ((report (my/repo-docs-generate)))
    (my/repo-docs--ensure-theme)
    (message "%s" (my/repo-docs--summary report)))
  (when (yes-or-no-p
         (format "Build the repository docs and upload to %s?  That folder becomes an exact copy of the build: anything else in it is deleted. "
                 my/repo-docs-remote))
    (my/repo-docs--build-and-upload)))

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
          (insert "Not regenerated: files that would make one page\n\n")
          (dolist (c (plist-get report :collisions))
            (insert "  " (string-join c "  /  ") "\n")))
         (t
          (insert (my/repo-docs--summary report) "\n\n")
          (if (plist-get report :unresolved)
              (progn
                (insert "Links to documents the site has no page for, and failed\nOrg exports:\n\n")
                (dolist (u (plist-get report :unresolved))
                  (insert (format "  %s  ->  %s\n" (car u) (cdr u)))))
            (insert "Every link to a document was resolved.\n")))))
      (special-mode)
      (goto-char (point-min)))
    (pop-to-buffer my/repo-docs-report-buffer)))

(defun my/repo-docs--after-save ()
  "Regenerate the site after a document of a repository is saved.
Only while the preview server runs: otherwise nobody is looking, and
`my/repo-docs-preview' regenerates anyway."
  (when (and my/repo-docs-regenerate-on-save
             (my/repo-docs--serving-p)
             (my/repo-docs--site-path-of buffer-file-name))
    (condition-case err
        (let ((report (my/repo-docs-generate)))
          (when (> (plist-get report :written) 0)
            (message "%s" (my/repo-docs--summary report))))
      (error (message "Repo docs: %s" (error-message-string err))))))

;; ============================================================
;; MENU (C-c n x r)
;; ============================================================

(transient-define-prefix my/repo-docs-menu ()
  "Documentation of the repositories as a Hugo site."
  [["Documents"
    ("f" "Find a document"      my/repo-docs-find)
    ("g" "Regenerate the site"  my/repo-docs-regenerate)
    ("o" "Site folder"          my/repo-docs-open-site)]
   ["Preview"
    ("v" "Preview in browser"   my/repo-docs-preview)
    ("s" "Stop the preview"     my/repo-docs-stop)
    ("l" "Last report"          my/repo-docs-report)]
   ["Server"
    ("w" "Open on the server"   my/repo-docs-open-on-server)
    ("p" "Publish to the server" my/repo-docs-publish)]
   [("q" "Quit" transient-quit-one)]])

;; ============================================================
;; SWITCH
;; ============================================================

(defconst my/repo-docs--menu-entries
  '((insert my/notes-export-menu "q" ("r" "Repo docs (Hugo) →" my/repo-docs-menu)))
  "Menu entries of this module, for `my/transient-entries'.
In the Export menu of 212-transient.el, before its Quit.")

(define-minor-mode my/repo-docs-mode
  "The repository docs as a module: regeneration on save, menu entry.
Turned off, neither, and the preview server is stopped; the commands
remain for M-x.  Customize saves the position in this machine's
settings."
  :global t
  :init-value t
  :group 'my/repo-docs
  (if my/repo-docs-mode
      (add-hook 'after-save-hook #'my/repo-docs--after-save)
    (remove-hook 'after-save-hook #'my/repo-docs--after-save)
    (when (my/repo-docs--serving-p)
      (delete-process (get-buffer-process my/repo-docs--server-buffer))
      (message "Repo docs off: preview server stopped")))
  (with-eval-after-load '212-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/repo-docs-mode my/repo-docs--menu-entries))))

;; The switch, applied with the position Customize read from this
;; machine's custom.el.
(my/repo-docs-mode (if my/repo-docs-mode 1 -1))

(provide '747-repo-docs)

;;; 747-repo-docs.el ends here
