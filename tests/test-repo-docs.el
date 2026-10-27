;;; test-repo-docs.el --- ERT tests for the repository docs site of 747-repo-docs -*- lexical-binding: t; -*-

;; Tests: 747-repo-docs

;;; Commentary:

;; 747-repo-docs.el turns the documents of several git repositories into
;; the content of one Hugo site, a section per repository: the eighth
;; module of TESTING.org, *Every module tested*, part 3.  With real git:
;; two repositories and a site folder made for each test.  Hugo is not
;; run -- the tests read what the module writes into the site.  The Org
;; tests need ox-hugo (installed for the workflow by ci-packages.el).
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
;; 716-org-export too: its filter of denote: links must be off during a
;; site export, and only shows when it is loaded, as at a real start.
(my/test-load-modules "747-repo-docs" "716-org-export")

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
-- that the pathspecs take and do not leave out, Markdown, plain text
and Org only, whatever the letter case of the extension."
  (my/rd-test--with-repos
      '(("emacs" (("README.md" . "# E\n") ("NOTES.TXT" . "n\n") ("x.org" . "* x\n") ("y.nix" . "{}\n")
                  ("hugo/theme/a.md" . "a\n") ("tests/t.md" . "t\n")
                  ("doc/b.md" . "b\n") (".gitignore" . "ignored.md\n"))
         :exclude ("hugo/" "tests/")))
    (let ((dir (expand-file-name "emacs" root)))
      (my/rd-test--write dir "new.md" "new\n")
      (my/rd-test--write dir "ignored.md" "secret\n"))
    (cl-letf (((symbol-function 'my/repo-docs--ox-hugo-p) (lambda () t)))
      (should (equal (mapcar #'car (plist-get (my/repo-docs--files) :files))
                     '("emacs/NOTES.TXT" "emacs/README.md" "emacs/doc/b.md" "emacs/new.md"
                       "emacs/x.org"))))))

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

;; ============================================================
;; ORG FILES
;; ============================================================

(defmacro my/rd-test--with-org (files &rest body)
  "Run BODY with a repository \"emacs\" holding FILES, Org included.
A second repository, \"nixos\", holds a README.md beside it.  Skipped
without ox-hugo.  The cache of Org exports starts empty."
  (declare (indent 1))
  `(progn
     (skip-unless (require 'ox-hugo nil t))
     (let ((my/repo-docs--org-cache (make-hash-table :test #'equal)))
       (my/rd-test--with-repos (list (list "emacs" ,files)
                                     (list "nixos" '(("README.md" . "# nixos\n"))))
         ,@body))))

(ert-deftest my/rd-test-org-page-title-and-text ()
  "An Org file becomes a page titled with its #+title, its headings one
level down (the title is the H1), without ox-hugo's front matter or its
own table of contents; without a title, the file name."
  (my/rd-test--with-org
      '(("TESTING.org" . "#+title: Testing rules\n#+options: toc:t\n\nIntro.\n\n* Where\nText.\n")
        ("notes.org" . "Just text.\n"))
    (my/repo-docs-generate)
    (let ((page (my/rd-test--page content "emacs/testing.md")))
      (should (string-match-p "\\`---\ntitle: \"Testing rules\"" page))
      (should (string-match-p "url: \"/emacs/testing/\"" page))
      (should (string-match-p "^## Where" page))
      (should-not (string-match-p "+++\\|Table of Contents\\|author" page)))
    (should (string-match-p "title: \"notes\""
                            (my/rd-test--page content "emacs/notes.md")))))

(ert-deftest my/rd-test-org-links ()
  "Links in an Org file: to another document of the repository, its
page, with the heading's custom id or slug; a missing heading, the page
without an anchor and no question; a document the site lacks, or out of
the repository, its description, reported; a `denote:' link, its
description only; an image, ox-hugo's, copied into the site.  A
document of another repository is out of the repository too."
  (my/rd-test--with-org
      '(("SAFETY.org" . "#+title: Safety\n\n* Publishing rules\nx\n* With id\n:PROPERTIES:\n:CUSTOM_ID: pub\n:END:\ny\n")
        ("README.md" . "# emacs\n\n[t](TESTING.org#where)\n")
        ("img/a.png" . "png")
        ("TESTING.org" . "#+title: Testing\n\n* Where\n[[file:SAFETY.org::*Publishing rules][s]] [[file:SAFETY.org::*With id][i]] [[file:SAFETY.org::#pub][c]] [[file:SAFETY.org::*Missing][m]] [[file:README.md][r]] [[file:GONE.org][g]] [[file:../other/x.org][o]] [[file:../nixos/README.md][n]] [[denote:20261023T100000][a note]]\n\n[[file:img/a.png]]\n"))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (p) (error "Asked: %s" p))))
      (let ((report (my/repo-docs-generate))
            (page (my/rd-test--page content "emacs/testing.md")))
        (dolist (expected '("[s](/emacs/safety/#publishing-rules)" "[i](/emacs/safety/#pub)"
                            "[c](/emacs/safety/#pub)" "[m](/emacs/safety/)" "[r](/emacs/)"))
          (should (string-match-p (regexp-quote expected) page)))
        (should (string-match-p " g o n a note" page))
        (should-not (string-match-p "20261023T100000\\|GONE\\|other/x\\|/nixos/" page))
        (should (string-match-p "/ox-hugo/a.png" page))
        (should (file-exists-p (expand-file-name "static/ox-hugo/a.png" site)))
        (should (equal (plist-get report :unresolved)
                       '(("emacs/TESTING.org" . "GONE.org")
                         ("emacs/TESTING.org" . "../other/x.org")
                         ("emacs/TESTING.org" . "../nixos/README.md"))))
        (should (string-match-p (regexp-quote "[t](/emacs/testing/#where)")
                                (my/rd-test--page content "emacs/_index.md")))))))

(ert-deftest my/rd-test-org-denote-links-text-only ()
  "A `denote:' link in an Org document is its description only, whether
Denote is loaded (its own link type) or not (Org reads a fuzzy link)."
  (let ((before (assoc "denote" org-link-parameters)))
    (unwind-protect
        (dolist (known '(nil t))
          ;; The link type must be registered for Org's parser, not
          ;; only bound: the parser reads a regexp made from the types.
          (setq org-link-parameters (assoc-delete-all "denote" org-link-parameters))
          (if known (org-link-set-parameters "denote") (org-link-make-regexps))
          (my/rd-test--with-org
              '(("A.org" . "#+title: A\n\nSee [[denote:20261023T100000][a note]] and [[denote:20261023T110000]].\n"))
            (my/repo-docs-generate)
            (let ((page (my/rd-test--page content "emacs/a.md")))
              (should (string-match-p "See a note and \\." page))
              (should-not (string-match-p "2026102\\|denote\\|BROKEN" page)))))
      (setq org-link-parameters (assoc-delete-all "denote" org-link-parameters))
      (when before (push before org-link-parameters))
      (org-link-make-regexps))))

(ert-deftest my/rd-test-org-shortcodes ()
  "In an Org document, a shortcode written in the text is shown as
written; the figure shortcode ox-hugo writes for an image runs."
  (my/rd-test--with-org
      '(("A.org" . "#+title: A\n\nWrite =[x]({{< relref \"y\" >}})=.\n\n[[file:a.png]]\n")
        ("a.png" . "png"))
    (my/repo-docs-generate)
    (let ((page (my/rd-test--page content "emacs/a.md")))
      (should (string-match-p (regexp-quote "{{</* relref \"y\" */>}}") page))
      (should (string-match-p (regexp-quote "{{< figure src=\"/ox-hugo/a.png\" >}}") page)))))

(ert-deftest my/rd-test-org-readme-is-folder-page ()
  "A README.org is its folder's page; its title stays in the text as an
H2 unless it only repeats the folder's name."
  (my/rd-test--with-org
      '(("docs/README.org" . "#+title: About the documents\n\nText.\n")
        ("guide/README.org" . "#+title: guide\n\nText.\n"))
    (my/repo-docs-generate)
    (let ((docs (my/rd-test--page content "emacs/docs/_index.md")))
      (should (string-match-p "title: \"docs/\"" docs))
      (should (string-match-p "^## About the documents$" docs)))
    (should-not (string-match-p "^##" (my/rd-test--page content "emacs/guide/_index.md")))))

(ert-deftest my/rd-test-org-export-cached ()
  "An Org file is exported again only when it changed or the set of
pages did; otherwise the session's cache serves it."
  (my/rd-test--with-org '(("A.org" . "#+title: A\n\nText.\n"))
    (let ((exports 0)
          (real (symbol-function 'my/repo-docs--org-export)))
      (cl-letf (((symbol-function 'my/repo-docs--org-export)
                 (lambda (&rest args) (setq exports (1+ exports)) (apply real args))))
        (my/repo-docs-generate)
        (my/repo-docs-generate)
        (should (= exports 1))
        (let ((file (expand-file-name "emacs/A.org" root)))
          (my/rd-test--write (file-name-directory file) "A.org" "#+title: A\n\nChanged text.\n")
          (set-file-times file (time-add (current-time) 10)))
        (my/repo-docs-generate)
        (should (= exports 2))
        (should (string-match-p "Changed text" (my/rd-test--page content "emacs/a.md")))
        (my/rd-test--write (expand-file-name "emacs" root) "B.md" "b\n")
        (my/repo-docs-generate)
        (should (= exports 3))))))

(ert-deftest my/rd-test-org-export-failure-reported ()
  "An Org file whose export fails gets a page saying so and is reported;
the other pages are written."
  (my/rd-test--with-org '(("A.org" . "#+title: A\n") ("B.md" . "# B\n"))
    (let ((real (symbol-function 'org-export-as)))
      (cl-letf (((symbol-function 'org-export-as)
                 (lambda (&rest _) (error "Broken table"))))
        (let ((report (my/repo-docs-generate)))
          (should (string-match-p "Export of emacs/A.org failed: Broken table"
                                  (my/rd-test--page content "emacs/a.md")))
          (should (assoc "emacs/A.org" (plist-get report :unresolved)))
          (should (file-exists-p (expand-file-name "emacs/b.md" content)))))
      (ignore real))))

(ert-deftest my/rd-test-org-left-out-without-ox-hugo ()
  "Without ox-hugo, Org files are left out and the summary says so; the
other documents are there."
  (my/rd-test--with-repos '(("emacs" (("A.org" . "* a\n") ("B.md" . "# B\n"))))
    (cl-letf (((symbol-function 'my/repo-docs--ox-hugo-p) #'ignore))
      (let ((report (my/repo-docs-generate)))
        (should (plist-get report :no-org))
        (should (string-match-p "ox-hugo is not installed" (my/repo-docs--summary report)))
        (should (equal (my/rd-test--pages content)
                       '("_index.md" "emacs/_index.md" "emacs/b.md")))))))

;; ============================================================
;; ADDRESSES AND PUBLISHING
;; ============================================================

(ert-deftest my/rd-test-preview-local-unless-network-name ()
  "The preview server listens on this machine only, unless a name in the
network is set: then on every interface, its pages under that name."
  (let ((my/repo-docs-site-directory "/tmp/site/")
        (my/repo-docs-port 1316)
        (my/repo-docs-hugo-program "hugo"))
    (let ((my/repo-docs-lan-host nil))
      (should (equal (my/repo-docs--server-command)
                     '("hugo" "server" "--source" "/tmp/site/" "--port" "1316"))))
    (let ((my/repo-docs-lan-host "laptop.lan"))
      (should (equal (my/repo-docs--server-command)
                     '("hugo" "server" "--source" "/tmp/site/" "--port" "1316"
                       "--bind" "0.0.0.0" "--baseURL" "http://laptop.lan/"))))))

(ert-deftest my/rd-test-open-on-server ()
  "`w' opens the current file's page at the server's address, the home
page for a file the site lacks, and refuses without an address."
  (my/rd-test--with-repos '(("nixos" (("README.md" . "r\n") ("docs/B.md" . "# B\n"))))
    (my/repo-docs-generate)
    (let ((opened nil))
      (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (setq opened url))))
        (let ((my/repo-docs-url "https://docs.example.org/"))
          (let ((buffer-file-name (expand-file-name "nixos/docs/B.md" root)))
            (my/repo-docs-open-on-server))
          (should (equal opened "https://docs.example.org/nixos/docs/b/"))
          (let ((buffer-file-name nil))
            (my/repo-docs-open-on-server))
          (should (equal opened "https://docs.example.org/")))
        (let ((my/repo-docs-url nil))
          (should-error (my/repo-docs-open-on-server) :type 'user-error))))))

(defmacro my/rd-test--publishing (remote &rest body)
  "Run BODY with the site uploading to REMOTE, nothing run for real.
`commands' holds the command lines started, in order; each process
ends at once with the status in `status' (0 at first).  `asked' holds
the questions asked, `answer' is the answer given (nil at first)."
  (declare (indent 1))
  `(my/rd-test--with-repos '(("nixos" (("README.md" . "r\n"))))
     (let ((my/repo-docs-remote ,remote)
           (my/repo-docs-url "https://docs.example.org/")
           (commands '())
           (status 0)
           (asked '())
           (answer nil))
       (cl-letf (((symbol-function 'executable-find) (lambda (name &rest _) name))
                 ((symbol-function 'my/repo-docs--ensure-theme) #'ignore)
                 ((symbol-function 'yes-or-no-p)
                  (lambda (prompt) (push prompt asked) answer))
                 ((symbol-function 'make-process)
                  (lambda (&rest args)
                    (setq commands (append commands (list (plist-get args :command))))
                    (let ((sentinel (plist-get args :sentinel))
                          (proc 'fake))
                      (cl-letf (((symbol-function 'process-status) (lambda (_) 'exit))
                                ((symbol-function 'process-exit-status) (lambda (_) status)))
                        (funcall sentinel proc "finished\n"))
                      proc))))
         ,@body))))

(ert-deftest my/rd-test-publish-refuses-home-and-root ()
  "1.5: no destination, a home folder or the root: refused before the
site is regenerated, built or uploaded."
  (dolist (remote '(nil "user@server:" "user@server:~" "user@server:/" "user@server:/home/user/"))
    (my/rd-test--publishing remote
      (should-error (my/repo-docs-publish) :type 'user-error)
      (should-not commands)
      (should-not asked)
      (should-not (file-exists-p content)))))

(ert-deftest my/rd-test-publish-asks-then-builds-and-uploads ()
  "1.5: the question names the server and says the folder becomes an
exact copy; no builds nothing; yes builds with Hugo at the server's
address, then mirrors the build with rsync --delete -- argument lists,
no shell."
  (my/rd-test--publishing "user@server:/var/www/docs/"
    (my/repo-docs-publish)
    (should (= 1 (length asked)))
    (should (string-match-p (regexp-quote "user@server:/var/www/docs/") (car asked)))
    (should (string-match-p "exact copy" (car asked)))
    (should-not commands)
    (setq answer t)
    (my/repo-docs-publish)
    (let ((public (expand-file-name "public/" site)))
      (should (equal commands
                     (list (list "hugo" "--source" site "--destination" public
                                 "--baseURL" "https://docs.example.org/"
                                 "--gc" "--minify" "--cleanDestinationDir")
                           (list "rsync" "-az" "--delete" "--" public
                                 "user@server:/var/www/docs/")))))))

(ert-deftest my/rd-test-publish-no-upload-after-failed-build ()
  "A build that fails uploads nothing."
  (my/rd-test--publishing "user@server:/var/www/docs/"
    (setq answer t status 1)
    (cl-letf (((symbol-function 'display-buffer) #'ignore))
      (my/repo-docs-publish))
    (should (= 1 (length commands)))
    (should (equal (car (car commands)) "hugo"))))

(ert-deftest my/rd-test-upload-refused-at-the-last-moment ()
  "1.5: the build-and-upload step itself refuses a home folder, whoever
calls it, starting nothing."
  (my/rd-test--publishing "user@server:"
    (should-error (my/repo-docs--build-and-upload) :type 'user-error)
    (should-not commands)))

(ert-deftest my/rd-test-publish-needs-server-address ()
  "Without the server's address the build would point at this machine:
refused."
  (my/rd-test--publishing "user@server:/var/www/docs/"
    (let ((my/repo-docs-url nil))
      (should-error (my/repo-docs-publish) :type 'user-error))
    (should-not commands)))

(provide 'test-repo-docs)
;;; test-repo-docs.el ends here
