;;; 46-blog.el --- Publish selected notes as a Hugo blog -*- lexical-binding: t; -*-
;;; Commentary:
;; Selected Denote notes become posts of a static Hugo site, which is
;; built locally and copied to a web server with rsync.  The Org side is
;; ox-hugo (kaushalmodi/ox-hugo), an established Org -> Hugo Markdown
;; exporter; this module adds only what is specific to a Denote notes
;; tree: which notes are public, how `denote:' links between them are
;; resolved, and what must never leave the machine.
;;
;; WHICH NOTES ARE PUBLIC
;; ----------------------
;; A note is published when BOTH hold:
;;   - its file name carries the Denote keyword `my/blog-keyword' (blog);
;;   - it lives in one of the silos listed in `my/blog-silos'.
;; The silo list is an allowlist, and `journal' is deliberately not on
;; it: a journal note tagged `blog' by mistake stays private.  The
;; keyword itself is removed from the tags the post shows.
;;
;; WHY THE EXPORT RUNS ON A COPY
;; -----------------------------
;; Each note is exported from a temporary buffer holding a copy of the
;; file, with an `#+export_file_name:' line added on top.  That line is
;; what gives the post a readable URL instead of the Denote file name,
;; and adding it to the note itself would store a derived value in the
;; note -- the thing the hub module refuses to do for the same reason.
;; The copy also keeps the export away from the live buffer: no mode
;; hooks, no live transclusions, no fonts.
;;
;; DENOTE LINKS
;; ------------
;; During an export started from this module, and only then:
;;   - a link to a public note becomes a Hugo `relref' to its post;
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
;; WHAT IS REFUSED
;; ---------------
;; A public note that `#+INCLUDE:'s a non-public note is not exported:
;; the included text would be published with it.  20-transclusion.el
;; pairs every `#+transclude:' with such an `#+INCLUDE:', so transcluding
;; a private note into a public one is caught here.  Two public notes
;; that would get the same URL are also refused, the newer one losing.
;;
;; THE SECTION DIRECTORY IS OWNED BY THIS MODULE
;; ---------------------------------------------
;; content/<my/blog-section>/ holds generated files only.  A full export
;; removes every .md file there that no public note produced, after a
;; confirmation, which is how removing the keyword unpublishes a note.
;; Hand-written pages (about, contact) belong elsewhere under content/.
;;
;; MENU (C-c n x b)
;; ----------------
;;   e  export this note          v  preview with `hugo server'
;;   d  dry run of a full export  s  stop the preview
;;   a  export every public note  p  export, build, upload
;;   o  site folder in Dired      l  last report
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
  "Publish selected notes as a Hugo blog."
  :group 'my/notes)

(defcustom my/blog-site-directory (expand-file-name "~/projects/blog/")
  "Root of the Hugo site, the directory holding hugo.toml.
Outside the notes tree on purpose: it is a git repository, and git
repositories are kept out of Syncthing's reach."
  :type 'directory
  :group 'my/blog)

(defcustom my/blog-section "posts"
  "Hugo section the notes are exported to, under content/.
This directory is owned by the module; see the Commentary."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-keyword "blog"
  "Denote keyword that marks a note as public."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-silos '("pks" "docu")
  "Silos a public note may live in, relative to the notes root.
An allowlist: a note elsewhere is never published, whatever its
keywords.  Leave `journal' and `inbox' off it."
  :type '(repeat string)
  :group 'my/blog)

(defcustom my/blog-url-source 'title
  "What the URL of a post is made from.
`title': the title part of the Denote file name, transliterated to
ASCII.  Readable, but renaming the note changes the URL.
`identifier': the Denote identifier.  Stable across renames, opaque."
  :type '(choice (const :tag "Title (readable)" title)
                 (const :tag "Identifier (stable)" identifier))
  :group 'my/blog)

(defcustom my/blog-remote nil
  "Rsync destination of the built site, for example
\"user@server:/var/www/blog/\".  The trailing slash matters: rsync
then copies the contents of public/ rather than the directory."
  :type '(choice (const :tag "Not set" nil) string)
  :group 'my/blog)

(defcustom my/blog-hugo-program "hugo"
  "Hugo executable."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-rsync-program "rsync"
  "Rsync executable."
  :type 'string
  :group 'my/blog)

(defcustom my/blog-preview-url "http://localhost:1313/"
  "Address `hugo server' listens on."
  :type 'string
  :group 'my/blog)

(defconst my/blog-report-buffer "*Blog export*"
  "Buffer holding the report of the last export.")

(defconst my/blog-preview-buffer "*Blog preview*"
  "Buffer of the running `hugo server' process.")

(defconst my/blog-publish-buffer "*Blog publish*"
  "Buffer of the build-and-upload process.")

(defconst my/blog--hugo-config-files
  '("hugo.toml" "hugo.yaml" "hugo.json"
    "config.toml" "config.yaml" "config.json" "config")
  "Names whose presence marks a directory as a Hugo site.")

(defvar my/blog--index nil
  "Identifier -> slug table of the notes being published.
Bound only while an export started from this module runs; the link
export function reads it.")

;; ============================================================
;; WHICH NOTES ARE PUBLIC
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

(defun my/blog-public-p (file)
  "Return non-nil when FILE is a note that may be published."
  (and (stringp file)
       (string-suffix-p ".org" file)
       (file-exists-p file)
       (string-prefix-p (my/blog--notes-root) (expand-file-name file))
       (not (my/blog--excluded-p file))
       (member (my/blog--silo-of file) my/blog-silos)
       (member my/blog-keyword (denote-extract-keywords-from-path file))
       t))

(defun my/blog--public-notes ()
  "Return every public note, sorted by file name (oldest first)."
  (let ((root (my/blog--notes-root))
        (files '()))
    (dolist (silo my/blog-silos)
      (let ((dir (expand-file-name silo root)))
        (when (file-directory-p dir)
          (dolist (file (directory-files-recursively dir "\\.org\\'"))
            (when (my/blog-public-p file)
              (push file files))))))
    ;; Denote file names start with the identifier, so this orders
    ;; notes by creation time and decides which of two colliding URLs
    ;; is kept: the older note's.
    (sort files (lambda (a b) (string< (file-name-nondirectory a)
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

(defun my/blog--private-includes (file)
  "Return the files FILE includes that are not public themselves."
  (seq-remove #'my/blog-public-p (my/blog--included-files file)))

;; ============================================================
;; PLAN
;; ============================================================

(defun my/blog--content-dir ()
  "Return content/<section>/ of the site."
  (file-name-as-directory
   (expand-file-name (concat "content/" my/blog-section)
                     (expand-file-name my/blog-site-directory))))

(defun my/blog--plan ()
  "Work out what a full export would do, without writing anything.
Returns a plist:
  :ready   list of (FILE . SLUG) to export
  :refused list of (FILE REASON) that will not be exported
  :stale   .md files in the section directory no note produces
  :index   identifier -> slug table of the notes in :ready"
  (let ((by-slug (make-hash-table :test #'equal))
        (index (make-hash-table :test #'equal))
        (ready '())
        (refused '()))
    (dolist (file (my/blog--public-notes))
      (let ((slug (my/blog--slug file))
            (private (my/blog--private-includes file)))
        (cond
         (private
          (push (list file (format "includes non-public: %s"
                                   (mapconcat #'abbreviate-file-name
                                              private ", ")))
                refused))
         ((gethash slug by-slug)
          (push (list file (format "URL /%s/%s/ already taken by %s"
                                   my/blog-section slug
                                   (file-name-nondirectory
                                    (gethash slug by-slug))))
                refused))
         (t
          (puthash slug file by-slug)
          (push (cons file slug) ready)))))
    (dolist (entry ready)
      (let ((id (denote-retrieve-filename-identifier (car entry))))
        (when id (puthash id (cdr entry) index))))
    (let* ((dir (my/blog--content-dir))
           (wanted (mapcar (lambda (e) (concat (cdr e) ".md")) ready))
           (stale (when (file-directory-p dir)
                    (seq-remove (lambda (f)
                                  (member (file-name-nondirectory f) wanted))
                                (directory-files dir t "\\.md\\'")))))
      (list :ready (nreverse ready)
            :refused (nreverse refused)
            :stale stale
            :index index))))

;; ============================================================
;; EXPORT
;; ============================================================

(defun my/blog--denote-link-export (link description format)
  "Export a `denote:' LINK with DESCRIPTION for the blog.
A link to a note in `my/blog--index' becomes a Hugo relref, keeping a
`::#custom-id' anchor; any other link becomes DESCRIPTION alone, so
nothing about a private note leaves the machine except the words the
public note itself uses for it.  FORMAT other than `md' gets the
description too: this function is only installed for Hugo exports."
  (let* ((parts (split-string link "::"))
         (id (car parts))
         (search (cadr parts))
         (slug (and my/blog--index (gethash id my/blog--index)))
         (text (or description "")))
    (if (and slug (eq format 'md))
        (format "[%s]({{< relref \"/%s/%s%s\" >}})"
                (if (string-empty-p text) slug text)
                my/blog-section slug
                (if (and search (string-prefix-p "#" search)) search ""))
      text)))

(defun my/blog--link-parameters ()
  "Return `org-link-parameters' with the blog's export for `denote'."
  (let* ((params (copy-alist org-link-parameters))
         (denote-params (copy-sequence (cdr (assoc "denote" params)))))
    (cons (cons "denote" (plist-put denote-params :export
                                    #'my/blog--denote-link-export))
          (assoc-delete-all "denote" params))))

(defun my/blog--drop-publish-keyword (tags _info)
  "Remove `my/blog-keyword' from TAGS: it marks the note, not the post."
  (remove my/blog-keyword tags))

(defun my/blog--require-ox-hugo ()
  "Load ox-hugo or stop with a readable error."
  (unless (require 'ox-hugo nil t)
    (user-error "ox-hugo is not installed (M-x package-install RET ox-hugo)")))

(defun my/blog--check-site ()
  "Stop unless `my/blog-site-directory' is a Hugo site."
  (let ((site (expand-file-name my/blog-site-directory)))
    (cond
     ((not (file-directory-p site))
      (user-error "Blog site not found: %s (see function_helper.org, Blog setup)"
                  site))
     ((not (seq-some (lambda (name) (file-exists-p (expand-file-name name site)))
                     my/blog--hugo-config-files))
      (user-error "No Hugo configuration in %s" site))
     ;; ox-hugo copies images into static/ and refuses to export a note
     ;; with an image when the directory is missing.  `hugo new site'
     ;; creates it, but git does not keep empty directories, so a fresh
     ;; clone of the site repository lacks it.
     (t (make-directory (expand-file-name "static" site) t)))))

(defun my/blog--check-program (program)
  "Stop unless PROGRAM is on PATH."
  (unless (executable-find program)
    (user-error "%s not found on PATH" program)))

(defun my/blog--export-file (file slug index)
  "Export FILE to the site as SLUG, resolving links through INDEX.
Returns the path of the Markdown file written."
  ;; Before the `let': its bindings read ox-hugo's own defaults.
  (my/blog--require-ox-hugo)
  (let ((my/blog--index index)
        (org-hugo-base-dir (file-name-as-directory
                            (expand-file-name my/blog-site-directory)))
        (org-hugo-section my/blog-section)
        (org-hugo-tag-processing-functions
         (append org-hugo-tag-processing-functions
                 (list #'my/blog--drop-publish-keyword)))
        (org-export-filter-link-functions
         (remq 'my/latex-filter-denote-link org-export-filter-link-functions))
        (org-link-parameters (my/blog--link-parameters)))
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
be missing from the post.  Returns the number of buffers saved."
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

(defun my/blog--report (write plan done failed removed)
  "Show the report of an export.
WRITE is nil for a dry run.  PLAN is from `my/blog--plan'; DONE lists
exported (FILE . SLUG); FAILED lists (FILE MESSAGE); REMOVED lists the
stale files deleted, or the symbol `kept' when deletion was declined."
  (let ((ready (plist-get plan :ready))
        (refused (plist-get plan :refused))
        (stale (plist-get plan :stale))
        (name (lambda (f) (file-name-nondirectory f))))
    (with-current-buffer (get-buffer-create my/blog-report-buffer)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+title: Blog export — %s, %s\n\n"
                        (if write "written" "dry run")
                        (format-time-string "%Y-%m-%d %H:%M"))
                (format "Site: %s\n\n" (abbreviate-file-name
                                         (expand-file-name my/blog-site-directory))))
        (let ((posts (if write done ready)))
          (insert (format "* %s (%d)\n"
                          (if write "Exported" "Would export") (length posts)))
          (when posts
            (insert (my/blog--table
                     (mapcar (lambda (e)
                               (list (funcall name (car e))
                                     (format "/%s/%s/" my/blog-section (cdr e))))
                             posts))
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
                              ((eq removed 'kept) "Not public any more, kept on request")
                              (t "Removed from the site"))
                        (length stale)))
        (dolist (f stale) (insert (format "- %s\n" (funcall name f))))
        (goto-char (point-min))
        (when (fboundp 'org-mode) (delay-mode-hooks (org-mode)))
        (setq buffer-read-only t)))
    (display-buffer my/blog-report-buffer)))

;; ============================================================
;; COMMANDS: EXPORT
;; ============================================================

(defun my/blog--run (write)
  "Export every public note.  With WRITE nil, only report the plan.
Returns non-nil when every planned note was exported."
  (my/blog--require-ox-hugo)
  (my/blog--check-site)
  (my/blog--save-notes)
  (let ((plan (my/blog--plan))
        (done '())
        (failed '())
        (removed nil))
    (when write
      (dolist (entry (plist-get plan :ready))
        (condition-case err
            (progn
              (my/blog--export-file (car entry) (cdr entry)
                                    (plist-get plan :index))
              (push entry done))
          (error (push (list (car entry) (error-message-string err)) failed))))
      (setq done (nreverse done)
            failed (nreverse failed))
      (let ((stale (plist-get plan :stale)))
        (setq removed
              (if (and stale
                       (not (yes-or-no-p
                             (format "Remove %d post(s) no longer public from the site? "
                                     (length stale)))))
                  'kept
                (dolist (f stale) (delete-file f))
                stale))))
    (my/blog--report write plan done failed removed)
    (message "Blog %s: %d post(s), %d refused%s"
             (if write "export" "dry run")
             (length (if write done (plist-get plan :ready)))
             (length (plist-get plan :refused))
             (if failed (format ", %d FAILED" (length failed)) ""))
    (null failed)))

;;;###autoload
(defun my/blog-export-all-dry-run ()
  "Report what a full export would write and remove, writing nothing."
  (interactive)
  (my/blog--run nil))

;;;###autoload
(defun my/blog-export-all ()
  "Export every public note and remove posts that are no longer public."
  (interactive)
  (my/blog--run t))

;;;###autoload
(defun my/blog-export-current ()
  "Export the note in the current buffer to the blog."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (my/blog-public-p file)
      (user-error "Not a public note: needs the keyword `%s' and a silo from %s"
                  my/blog-keyword (string-join my/blog-silos ", ")))
    (my/blog--require-ox-hugo)
    (my/blog--check-site)
    (when (buffer-modified-p) (save-buffer))
    (let* ((plan (my/blog--plan))
           (entry (assoc file (plist-get plan :ready)))
           (refusal (assoc file (plist-get plan :refused))))
      (cond
       (refusal (user-error "Not exported: %s" (cadr refusal)))
       ((null entry) (user-error "Not exported: note missing from the plan"))
       (t
        (my/blog--export-file file (cdr entry) (plist-get plan :index))
        (message "Exported to /%s/%s/" my/blog-section (cdr entry)))))))

;;;###autoload
(defun my/blog-show-report ()
  "Show the report of the last export."
  (interactive)
  (if (get-buffer my/blog-report-buffer)
      (display-buffer my/blog-report-buffer)
    (message "No blog export has been run in this session")))

;;;###autoload
(defun my/blog-open-site ()
  "Open the Hugo site directory in Dired."
  (interactive)
  (let ((site (expand-file-name my/blog-site-directory)))
    (if (file-directory-p site)
        (dired site)
      (message "Blog site not found: %s" site))))

;; ============================================================
;; COMMANDS: PREVIEW AND PUBLISH
;; ============================================================

;;;###autoload
(defun my/blog-preview ()
  "Serve the site with `hugo server' and open it in the browser.
The server rebuilds on every change, so exporting a note while it runs
is enough to see the result.  Drafts are shown."
  (interactive)
  (my/blog--check-site)
  (my/blog--check-program my/blog-hugo-program)
  (let ((proc (get-buffer-process my/blog-preview-buffer)))
    (if (and proc (process-live-p proc))
        (browse-url my/blog-preview-url)
      (make-process
       :name "blog-preview"
       :buffer (get-buffer-create my/blog-preview-buffer)
       :command (list my/blog-hugo-program "server"
                      "--source" (expand-file-name my/blog-site-directory)
                      "--buildDrafts" "--navigateToChanged")
       :noquery t)
      ;; The first build takes a moment; opening the page at once shows
      ;; a connection error instead.
      (run-at-time 2 nil #'browse-url my/blog-preview-url)
      (message "Hugo server starting - output in %s" my/blog-preview-buffer))))

;;;###autoload
(defun my/blog-preview-stop ()
  "Stop the `hugo server' started by `my/blog-preview'."
  (interactive)
  (let ((proc (get-buffer-process my/blog-preview-buffer)))
    (if (and proc (process-live-p proc))
        (progn (delete-process proc) (message "Hugo server stopped"))
      (message "No Hugo server running"))))

(defun my/blog--publish-sentinel (proc _event)
  "Report the end of the build-and-upload PROC."
  (when (memq (process-status proc) '(exit signal))
    (if (zerop (process-exit-status proc))
        (message "Blog published to %s" my/blog-remote)
      (display-buffer my/blog-publish-buffer)
      (message "Blog publish FAILED (exit %d) - see %s"
               (process-exit-status proc) my/blog-publish-buffer))))

;;;###autoload
(defun my/blog-publish ()
  "Export every public note, build the site and upload it.
The upload mirrors public/ to `my/blog-remote' with rsync --delete, so
the server ends up holding exactly what was built."
  (interactive)
  (unless (and (stringp my/blog-remote) (not (string-empty-p my/blog-remote)))
    (user-error "Set `my/blog-remote' first, e.g. \"user@server:/var/www/blog/\""))
  (my/blog--check-program my/blog-hugo-program)
  (my/blog--check-program my/blog-rsync-program)
  (unless (my/blog--run t)
    (unless (yes-or-no-p "Some notes failed to export.  Publish anyway? ")
      (user-error "Publish cancelled - see %s" my/blog-report-buffer)))
  (when (yes-or-no-p (format "Build and upload to %s? " my/blog-remote))
    (let* ((site (expand-file-name my/blog-site-directory))
           (public (file-name-as-directory (expand-file-name "public" site)))
           (command (format "%s --source %s --gc --minify --cleanDestinationDir && %s -az --delete %s %s"
                            (shell-quote-argument my/blog-hugo-program)
                            (shell-quote-argument site)
                            (shell-quote-argument my/blog-rsync-program)
                            (shell-quote-argument public)
                            (shell-quote-argument my/blog-remote))))
      (with-current-buffer (get-buffer-create my/blog-publish-buffer)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert command "\n\n")))
      (make-process
       :name "blog-publish"
       :buffer my/blog-publish-buffer
       :command (list shell-file-name shell-command-switch command)
       :noquery t
       :sentinel #'my/blog--publish-sentinel)
      (message "Building and uploading..."))))

;; ============================================================
;; MENU  (C-c n x b)
;; Docs: ~/.emacs.d/function_helper.org::#menu-blog
;; ============================================================

(transient-define-prefix my/blog-menu ()
  "Publish notes as a Hugo blog."
  [["Export"
    ("e" "This note"               my/blog-export-current)
    ("d" "All - dry run"           my/blog-export-all-dry-run)
    ("a" "All public notes"        my/blog-export-all)]
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
