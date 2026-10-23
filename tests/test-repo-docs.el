;;; test-repo-docs.el --- ERT tests for the repository docs site of 47-repo-docs -*- lexical-binding: t; -*-

;; Tests: 47-repo-docs

;;; Commentary:

;; 47-repo-docs.el turns the documents of several git repositories into
;; the content of one Hugo site, a section per repository: the eighth
;; module of TESTING.org, *Every module tested*, part 3.  With real git:
;; two repositories and a site folder made for each test.  Hugo is not
;; run -- the tests read what the module writes into the site.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-repo-docs.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  Needs git on PATH.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "47-repo-docs")

;; ============================================================
;; FIXTURE
;; ============================================================

(defun my/rd-test--git (dir &rest args)
  "Run git with ARGS in DIR; signal on failure."
  (with-temp-buffer
    (let ((default-directory (file-name-as-directory dir)))
      (unless (eq 0 (apply #'call-process "git" nil t nil
                           "-c" "user.name=test" "-c" "user.email=test@test"
                           "-c" "init.defaultBranch=main" args))
        (error "git %S failed: %s" args (buffer-string))))))

(defun my/rd-test--write (dir rel text)
  "Write TEXT to REL under DIR, creating folders; return the path."
  (let ((file (expand-file-name rel dir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    file))

(defun my/rd-test--repo (dir files)
  "Make a git repository in DIR holding FILES, (REL . TEXT), committed."
  (make-directory dir t)
  (my/rd-test--git dir "init" "-q")
  (dolist (file files) (my/rd-test--write dir (car file) (cdr file)))
  (my/rd-test--git dir "add" "-A")
  (my/rd-test--git dir "commit" "-q" "-m" "init"))

(defmacro my/rd-test--with-repos (repos &rest body)
  "Run BODY with the repositories REPOS and an empty site folder.
REPOS is a list of (NAME FILES . PROPERTIES): each is made a git
repository in a temporary folder holding FILES, (REL . TEXT), and
listed in `my/repo-docs-repositories' with PROPERTIES.  Binds `root'
\(the folder holding the repositories, one folder per NAME), `site'
and `content'."
  (declare (indent 1))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-repos-" t)))
          (site (file-name-as-directory (make-temp-file "mypks-docs-site-" t)))
          (content (expand-file-name "content/" site))
          (my/repo-docs-site-directory site)
          (my/repo-docs-title "Repositories")
          (my/repo-docs-port 1316)
          (my/repo-docs--last-report nil)
          (my/repo-docs--last-map nil)
          (my/repo-docs-repositories
           (mapcar (lambda (repo)
                     (let ((dir (expand-file-name (car repo) root)))
                       (my/rd-test--repo dir (nth 1 repo))
                       (cons (car repo) (append (list :directory dir) (nthcdr 2 repo)))))
                   ,repos))
          (inhibit-message t))
     (unwind-protect
         (progn ,@body)
       (delete-directory root t)
       (delete-directory site t))))

(defun my/rd-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/rd-test--page (content rel)
  "Return the generated page REL under CONTENT."
  (my/rd-test--read (expand-file-name rel content)))

(defun my/rd-test--pages (content)
  "Return the generated files under CONTENT, relative and sorted."
  (sort (mapcar (lambda (f) (file-relative-name f content))
                (directory-files-recursively content ""))
        #'string<))

;; ============================================================
;; WHICH FILES
;; ============================================================

(ert-deftest my/rd-test-files-from-git-and-pathspecs ()
  "Files are those git would commit -- tracked, or new and not ignored
-- that the pathspecs take and do not leave out, Markdown and plain text
only, whatever the letter case of the extension."
  (my/rd-test--with-repos
      '(("emacs" (("README.md" . "# E\n") ("NOTES.TXT" . "n\n") ("x.org" . "* x\n")
                  ("hugo/theme/a.md" . "a\n") ("tests/t.md" . "t\n")
                  ("doc/b.md" . "b\n") (".gitignore" . "ignored.md\n"))
         :exclude ("hugo/" "tests/")))
    (let ((dir (expand-file-name "emacs" root)))
      (my/rd-test--write dir "new.md" "new\n")
      (my/rd-test--write dir "ignored.md" "secret\n"))
    (should (equal (mapcar #'car (plist-get (my/repo-docs--files) :files))
                   '("emacs/NOTES.TXT" "emacs/README.md" "emacs/doc/b.md" "emacs/new.md")))))

(ert-deftest my/rd-test-include-narrows ()
  "`:include' replaces the default: only what it names is taken."
  (my/rd-test--with-repos
      '(("nixos" (("README.md" . "r\n") ("docs/a.md" . "a\n") ("notes.txt" . "n\n"))
         :include ("docs/")))
    (should (equal (mapcar #'car (plist-get (my/repo-docs--files) :files))
                   '("nixos/docs/a.md")))))

(ert-deftest my/rd-test-missing-repository-left-out ()
  "A repository missing on this machine is left out and named; when
none is there, nothing is generated."
  (my/rd-test--with-repos '(("nixos" (("README.md" . "r\n"))))
    (let ((my/repo-docs-repositories
           (append my/repo-docs-repositories
                   (list (list "gone" :directory (expand-file-name "gone" root))))))
      (let ((found (my/repo-docs--files)))
        (should (equal (mapcar #'car (plist-get found :files)) '("nixos/README.md")))
        (should (equal (plist-get found :missing) '("gone"))))
      (should (equal (plist-get (my/repo-docs-generate) :missing) '("gone"))))
    (let ((my/repo-docs-repositories
           (list (list "gone" :directory (expand-file-name "gone" root)))))
      (should-error (my/repo-docs-generate) :type 'user-error))))

(ert-deftest my/rd-test-repository-names-checked ()
  "A name that cannot be a URL part, or used twice, stops the run."
  (dolist (repos '((("NixOS" :directory "/tmp/x/"))
                   (("a/b" :directory "/tmp/x/"))
                   (("a" :directory "/tmp/x/") ("a" :directory "/tmp/y/"))
                   (("a"))))
    (let ((my/repo-docs-repositories repos))
      (should-error (my/repo-docs--check-repositories) :type 'user-error))))

;; ============================================================
;; PAGES AND ADDRESSES
;; ============================================================

(ert-deftest my/rd-test-each-repository-a-section ()
  "Each repository is a section under its name: its root files are pages
in it, its folders sections in it, its README the section's page; the
home page lists the repositories."
  (my/rd-test--with-repos
      '(("nixos" (("README.md" . "# nixos\n\nIntro.\n") ("CLAUDE.md" . "# Notes for Claude\n")
                  ("docs/BACKUPS.md" . "# Backups\n") ("docs/devices/README.md" . "# Devices\n")))
        ("emacs" (("README.md" . "# Emacs configuration\n"))))
    (my/repo-docs-generate)
    (should (equal (my/rd-test--pages content)
                   '("_index.md" "emacs/_index.md" "nixos/_index.md" "nixos/claude.md"
                     "nixos/docs/_index.md" "nixos/docs/backups.md"
                     "nixos/docs/devices/_index.md")))
    (should (string-match-p "title: \"Repositories\"" (my/rd-test--page content "_index.md")))
    (should (string-match-p "{{< toc-tree >}}" (my/rd-test--page content "_index.md")))
    (let ((page (my/rd-test--page content "nixos/claude.md")))
      (should (string-match-p "title: \"Notes for Claude\"" page))
      (should (string-match-p "url: \"/nixos/claude/\"" page)))
    ;; A README's H1 that repeats the section's name goes; another stays
    ;; as an H2 under it.
    (let ((page (my/rd-test--page content "nixos/_index.md")))
      (should (string-match-p "title: \"nixos\"" page))
      (should-not (string-match-p "^#" page)))
    (let ((page (my/rd-test--page content "emacs/_index.md")))
      (should (string-match-p "title: \"emacs\"" page))
      (should (string-match-p "^## Emacs configuration$" page)))
    (should (string-match-p "title: \"devices/\""
                            (my/rd-test--page content "nixos/docs/devices/_index.md")))))

(ert-deftest my/rd-test-repository-title-and-order ()
  "A repository's `:title' names its section; the sections come in the
order of `my/repo-docs-repositories', not by name."
  (my/rd-test--with-repos
      '(("zeta" (("a.md" . "a\n")) :title "NixOS configuration")
        ("alpha" (("b.md" . "b\n"))))
    (my/repo-docs-generate)
    (let ((zeta (my/rd-test--page content "zeta/_index.md"))
          (alpha (my/rd-test--page content "alpha/_index.md")))
      (should (string-match-p "title: \"NixOS configuration\"" zeta))
      (should (string-match-p "weight: 10" zeta))
      (should (string-match-p "weight: 20" alpha)))))

(ert-deftest my/rd-test-file-named-like-folder-is-its-page ()
  "CHANGELOG.md beside changelog/ is the folder's page -- otherwise the
two would get one URL -- unless the folder has a README: then the run
stops, writing nothing."
  (my/rd-test--with-repos
      '(("emacs" (("CHANGELOG.md" . "# Changelog\n\nIndex.\n")
                  ("changelog/2026-10.md" . "# October\n"))))
    (my/repo-docs-generate)
    (should (equal (my/rd-test--pages content)
                   '("_index.md" "emacs/_index.md" "emacs/changelog/2026-10.md"
                     "emacs/changelog/_index.md")))
    (let ((page (my/rd-test--page content "emacs/changelog/_index.md")))
      (should (string-match-p "title: \"changelog/\"" page))
      (should (string-match-p "Index\\." page)))
    (should (equal (my/repo-docs--url-for-file
                    (expand-file-name "emacs/CHANGELOG.md" root))
                   "http://localhost:1316/emacs/changelog/")))
  (my/rd-test--with-repos
      '(("emacs" (("CHANGELOG.md" . "c\n") ("changelog/README.md" . "r\n"))))
    (should-error (my/repo-docs-generate) :type 'user-error)
    (should-not (file-exists-p content))))

(ert-deftest my/rd-test-collisions-refused ()
  "Two files that would make one page stop the run before anything is
written: names differing in letter case, one name in two kinds."
  (dolist (files '((("Guide.md" . "a\n") ("guide.md" . "b\n"))
                   (("notes.md" . "a\n") ("notes.txt" . "b\n"))
                   (("README.md" . "a\n") ("README.txt" . "b\n"))))
    (my/rd-test--with-repos (list (list "nixos" files))
      (should-error (my/repo-docs-generate) :type 'user-error)
      (should-not (file-exists-p content))
      (should (plist-get my/repo-docs--last-report :collisions)))))

(ert-deftest my/rd-test-plain-text-preformatted ()
  "A plain-text file is shown as it is, titled with its name, in a block
that a fence inside it cannot close."
  (my/rd-test--with-repos
      '(("nixos" (("notes.txt" . "# not a title\n```\n[x](a.md)\n"))))
    (my/repo-docs-generate)
    (let ((page (my/rd-test--page content "nixos/notes.md")))
      (should (string-match-p "title: \"notes\"" page))
      (should (string-match-p (regexp-quote "````text\n# not a title\n```\n[x](a.md)\n````") page)))))

(ert-deftest my/rd-test-shortcodes-shown-as-written ()
  "A Hugo shortcode written in a document -- in code, in plain text --
is escaped, so Hugo shows it instead of running it (an unknown page in
a relref fails the whole build); one already escaped stays as it is;
the module's own toc-tree runs."
  (my/rd-test--with-repos
      '(("emacs" (("a.md" . "# A\n\nUse `{{< relref \"x\" >}}` or {{% note %}}, not {{</* y */>}}.\n")
                  ("b.txt" . "{{< relref \"z\" >}}\n")
                  ("sub/c.md" . "# C\n"))))
    (my/repo-docs-generate)
    (should (string-match-p (regexp-quote "Use `{{</* relref \"x\" */>}}` or {{%/* note */%}}, not {{</* y */>}}.")
                            (my/rd-test--page content "emacs/a.md")))
    (should (string-match-p (regexp-quote "{{</* relref \"z\" */>}}")
                            (my/rd-test--page content "emacs/b.md")))
    (should (string-match-p (regexp-quote "{{< toc-tree >}}")
                            (my/rd-test--page content "emacs/sub/_index.md")))))

;; ============================================================
;; LINKS
;; ============================================================

(ert-deftest my/rd-test-links-rewritten-within-repository ()
  "Relative links to documents and folders lead to their pages, anchors
kept, in inline links and reference definitions; links in code blocks
are left alone; a link that leaves the repository, or names a document
the site lacks, is left as written and reported."
  (my/rd-test--with-repos
      `(("nixos" (("README.md" . ,(concat "# nixos\n\n"
                                          "[b](docs/BACKUPS.md#tests) [d](docs/devices/) "
                                          "[t](notes.txt) [g](docs/GONE.md) "
                                          "[e](../emacs/README.md)\n\n"
                                          "[ref]: docs/BACKUPS.md\n\n"
                                          "```\n[c](docs/BACKUPS.md)\n```\n"))
                  ("notes.txt" . "n\n")
                  ("docs/BACKUPS.md" . "# Backups\n\n[up](../README.md)\n")
                  ("docs/devices/README.md" . "# Devices\n")))
        ("emacs" (("README.md" . "# E\n"))))
    (let ((report (my/repo-docs-generate)))
      (let ((home (my/rd-test--page content "nixos/_index.md")))
        (should (string-match-p (regexp-quote "[b](/nixos/docs/backups/#tests)") home))
        (should (string-match-p (regexp-quote "[d](/nixos/docs/devices/)") home))
        (should (string-match-p (regexp-quote "[t](/nixos/notes/)") home))
        (should (string-match-p (regexp-quote "[g](docs/GONE.md)") home))
        (should (string-match-p (regexp-quote "[e](../emacs/README.md)") home))
        (should (string-match-p (regexp-quote "[ref]: /nixos/docs/backups/") home))
        (should (string-match-p (regexp-quote "[c](docs/BACKUPS.md)") home)))
      (should (string-match-p (regexp-quote "[up](/nixos/)")
                              (my/rd-test--page content "nixos/docs/backups.md")))
      (should (equal (plist-get report :unresolved)
                     '(("nixos/README.md" . "docs/GONE.md")
                       ("nixos/README.md" . "../emacs/README.md")))))))

;; ============================================================
;; REGENERATING
;; ============================================================

(ert-deftest my/rd-test-regeneration-writes-only-changes-and-prunes ()
  "A second run writes nothing; a document gone from the repository
loses its page; what the module did not write in content/ goes too,
while the rest of the site stays."
  (my/rd-test--with-repos
      '(("nixos" (("README.md" . "r\n") ("a.md" . "# A\n") ("b.md" . "# B\n"))))
    (my/repo-docs-generate)
    (should (= 0 (plist-get (my/repo-docs-generate) :written)))
    (my/rd-test--write site "static/keep.txt" "k")
    (my/rd-test--write content "stray.md" "s")
    (delete-file (expand-file-name "nixos/b.md" root))
    (let ((report (my/repo-docs-generate)))
      (should (= 2 (plist-get report :deleted))))
    (should (equal (my/rd-test--pages content)
                   '("_index.md" "nixos/_index.md" "nixos/a.md")))
    (should (file-exists-p (expand-file-name "static/keep.txt" site)))
    (should (file-exists-p (expand-file-name "hugo.toml" site)))))

(ert-deftest my/rd-test-file-page-addresses ()
  "A document's site path and page address; nil outside the
repositories and for a kind the site does not show."
  (my/rd-test--with-repos
      '(("nixos" (("README.md" . "r\n") ("docs/BACKUPS.md" . "b\n") ("x.nix" . "{}\n"))))
    (my/repo-docs-generate)
    (let ((dir (expand-file-name "nixos/" root)))
      (should (equal (my/repo-docs--site-path-of (expand-file-name "docs/BACKUPS.md" dir))
                     "nixos/docs/BACKUPS.md"))
      (should (equal (my/repo-docs--url-for-file (expand-file-name "docs/BACKUPS.md" dir))
                     "http://localhost:1316/nixos/docs/backups/"))
      (should (equal (my/repo-docs--url-for-file (expand-file-name "README.md" dir))
                     "http://localhost:1316/nixos/"))
      (should-not (my/repo-docs--site-path-of (expand-file-name "x.nix" dir)))
      (should-not (my/repo-docs--site-path-of (expand-file-name "other.md" site))))))

(ert-deftest my/rd-test-save-regenerates-only-while-serving ()
  "Saving a document regenerates the site only while the preview server
runs; a file outside the repositories never."
  (my/rd-test--with-repos '(("nixos" (("README.md" . "r\n"))))
    (let ((runs 0)
          (serving nil))
      (cl-letf (((symbol-function 'my/repo-docs--serving-p) (lambda () serving))
                ((symbol-function 'my/repo-docs-generate)
                 (lambda () (setq runs (1+ runs)) (list :written 0))))
        (let ((buffer-file-name (expand-file-name "nixos/README.md" root)))
          (my/repo-docs--after-save)
          (should (= runs 0))
          (setq serving t)
          (my/repo-docs--after-save)
          (should (= runs 1)))
        (let ((buffer-file-name (expand-file-name "elsewhere.md" site)))
          (my/repo-docs--after-save)
          (should (= runs 1)))))))

(provide 'test-repo-docs)
;;; test-repo-docs.el ends here
