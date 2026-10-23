;;; test-safety.el --- ERT tests for the rules of SAFETY.org -*- lexical-binding: t; -*-

;; Tests: 00-core 05-notes 46-blog

;;; Commentary:

;; One test per rule or finding of SAFETY.org; the rule's number is in
;; the test's name and docstring.  Each was shown to fail with its
;; safeguard taken out (CHANGELOG.md).  This file starts with the three
;; findings decided on 2026-10-19:
;;
;;   F1  a note git does not track goes to the trash, not away for good;
;;   F2  no upload to a home folder or the root, and the question says
;;       the upload replaces what is there;
;;   F3  a theme cloned with git is checked out at its pinned commit.
;;
;; Then the rules of publishing, 1.1-1.4 and 1.6 (2026-10-23g), on a
;; notes tree and a Hugo folder made for each test; nothing is uploaded.
;;
;; Needs git, and ox-hugo for the page test of 1.4; the modules load in
;; the sandbox of tests/helper.el, Denote and ox-hugo from the installed
;; packages.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-safety.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "05-notes" "46-blog")

(defun my/safety-test--git (dir &rest args)
  "Run git with ARGS in DIR; return its output, or signal on failure."
  (with-temp-buffer
    (let ((default-directory (file-name-as-directory dir)))
      (unless (eq 0 (apply #'call-process "git" nil t nil
                           "-c" "user.name=test" "-c" "user.email=test@test"
                           "-c" "init.defaultBranch=main" args))
        (error "git %S failed: %s" args (buffer-string)))
      (string-trim (buffer-string)))))

;; ============================================================
;; F1 -- 2.1: DELETING A NOTE
;; ============================================================

(ert-deftest my/safety-test-2.1-untracked-note-to-trash ()
  "2.1, F1: a note git does not track goes to the trash."
  (let* ((dir (make-temp-file "mypks-notes-" t))
         (trash (make-temp-file "mypks-trash-" t))
         (trash-directory trash)
         (note (expand-file-name "20261019T120000--a-note.org" dir)))
    (with-temp-file note (insert "#+title: a note\n"))
    (should (equal (my/denote--delete-file note) "trash"))
    (should-not (file-exists-p note))
    (should (file-exists-p (expand-file-name (file-name-nondirectory note) trash)))
    (delete-directory dir t)
    (delete-directory trash t)))

(ert-deftest my/safety-test-2.1-tracked-note-to-trash ()
  "2.1: a tracked note goes to the trash too, with what was written since
its last commit; git still has the committed version (since 2026-10-24;
before, `git rm -f' lost the uncommitted text)."
  (skip-unless (executable-find "git"))
  (let* ((dir (make-temp-file "mypks-notes-" t))
         (trash (make-temp-file "mypks-trash-" t))
         (trash-directory trash)
         (note (expand-file-name "20261019T120000--tracked.org" dir)))
    (my/safety-test--git dir "init" "--quiet")
    (with-temp-file note (insert "#+title: tracked\n"))
    (my/safety-test--git dir "add" ".")
    (my/safety-test--git dir "commit" "--quiet" "-m" "note")
    (with-temp-file note (insert "#+title: tracked\nWritten since the commit.\n"))
    (let ((default-directory (file-name-as-directory dir)))
      (should (equal (my/denote--delete-file note) "trash")))
    (should-not (file-exists-p note))
    (should (equal (with-temp-buffer
                     (insert-file-contents (expand-file-name (file-name-nondirectory note) trash))
                     (buffer-string))
                   "#+title: tracked\nWritten since the commit.\n"))
    (should (string-match-p "tracked"
                            (my/safety-test--git dir "show" "HEAD:20261019T120000--tracked.org")))
    (delete-directory dir t)
    (delete-directory trash t)))

;; ============================================================
;; F2 -- 1.5: UPLOADING A SITE
;; ============================================================

(ert-deftest my/safety-test-1.5-home-and-root-refused ()
  "1.5, F2: a home folder or the root is no upload destination."
  (dolist (remote '("user@server:" "user@server:~" "user@server:~/" "server:/"
                    "server:/root/" "user@server:/home/bob" "user@server:/home/bob/"
                    "server:/Users/bob/" "server:~bob" "~" "~/"))
    (should (my/blog--remote-problem remote)))
  (should (my/blog--remote-problem (expand-file-name "~"))))

(ert-deftest my/safety-test-1.5-site-folders-allowed ()
  "1.5: a folder of its own on the server is accepted."
  (dolist (remote '("user@server:/var/www/blog/" "server:/home/bob/www/"
                    "user@server:~/www/blog/" "/srv/site/"))
    (should-not (my/blog--remote-problem remote))))

(ert-deftest my/safety-test-1.5-upload-refused-at-the-last-moment ()
  "1.5: the build-and-upload step itself refuses, whoever calls it."
  (let ((my/blog-sites '(("s" :directory "/tmp/s/" :remote "user@server:")))
        (started nil))
    (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (setq started t))))
      (should-error (my/blog--build-and-upload "s") :type 'user-error))
    (should-not started)))

;; ============================================================
;; F3 -- 3.3: THEMES INSTALLED WITH GIT
;; ============================================================

(defun my/safety-test--theme-repo ()
  "Make a git repository with two commits; return (DIR FIRST SECOND)."
  (let ((dir (make-temp-file "mypks-theme-" t)))
    (my/safety-test--git dir "init" "--quiet")
    (with-temp-file (expand-file-name "theme.toml" dir) (insert "name = \"one\"\n"))
    (my/safety-test--git dir "add" ".")
    (my/safety-test--git dir "commit" "--quiet" "-m" "one")
    (let ((first (my/safety-test--git dir "rev-parse" "HEAD")))
      (with-temp-file (expand-file-name "theme.toml" dir) (insert "name = \"two\"\n"))
      (my/safety-test--git dir "commit" "--quiet" "-am" "two")
      (list dir first (my/safety-test--git dir "rev-parse" "HEAD")))))

(defun my/safety-test--install (theme target)
  "Install THEME into TARGET as a sync would; return the result passed on."
  (let ((result 'pending))
    (puthash target (list (lambda (ok) (setq result ok))) my/blog--theme-installs)
    (my/blog--install-theme-git '("site") theme target)
    (with-timeout (60 (error "Theme install did not finish"))
      (while (eq result 'pending)
        (accept-process-output nil 0.1)))
    result))

(ert-deftest my/safety-test-3.3-theme-at-its-pinned-commit ()
  "3.3, F3: a cloned theme is at its pinned commit, not the newest."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,first ,_second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (should (eq t (my/safety-test--install (list "t" repo first) target)))
    (should (equal (my/safety-test--git target "rev-parse" "HEAD") first))
    (should-not (my/blog--theme-pin-mismatch (list "t" repo first) target))
    (delete-directory repo t)))

(ert-deftest my/safety-test-3.3-unknown-commit-leaves-nothing ()
  "3.3: a pin the repository lacks installs nothing."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,_first ,_second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (should-not (my/safety-test--install
                 (list "t" repo "0123456789abcdef0123456789abcdef01234567") target))
    (should-not (file-exists-p target))
    (delete-directory repo t)))

(ert-deftest my/safety-test-3.3-moved-theme-is-noticed ()
  "3.3: a theme folder at another commit than its pin is noticed."
  (skip-unless (executable-find "git"))
  (pcase-let* ((`(,repo ,first ,second) (my/safety-test--theme-repo))
               (target (expand-file-name "themes/t" (make-temp-file "mypks-site-" t))))
    (my/safety-test--git repo "clone" "--quiet" repo target)
    (should (equal (my/blog--theme-pin-mismatch (list "t" repo first) target) second))
    (delete-directory repo t)))

;; ============================================================
;; 2.1: THE QUESTION BEFORE DELETING A NOTE
;; ============================================================

(defmacro my/safety-test--with-note (var &rest body)
  "Run BODY in a buffer visiting a new untracked note, its file in VAR.
Deleted files go to a temporary trash, bound as `trash'."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "mypks-notes-" t))
          (trash (make-temp-file "mypks-trash-" t))
          (trash-directory trash)
          (,var (expand-file-name "20261020T100000--to-delete.org" dir)))
     (with-temp-file ,var (insert "#+title: to delete\n"))
     (unwind-protect
         (with-current-buffer (find-file-noselect ,var)
           ,@body)
       (when-let* ((buffer (get-file-buffer ,var))) (kill-buffer buffer))
       (delete-directory dir t)
       (delete-directory trash t))))

(ert-deftest my/safety-test-2.1-no-answer-deletes-nothing ()
  "2.1: answering no to the question leaves the note where it is."
  (my/safety-test--with-note note
    (let ((my/confirm-deletion 'ask) (asked nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) (setq asked t) nil)))
        (my/denote-delete-note))
      (should asked)
      (should (file-exists-p note)))))

(ert-deftest my/safety-test-2.1-yes-answer-deletes-to-trash ()
  "2.1: answering yes deletes the note, to the trash."
  (my/safety-test--with-note note
    (let ((my/confirm-deletion 'ask))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (my/denote-delete-note))
      (should-not (file-exists-p note))
      (should (file-exists-p (expand-file-name (file-name-nondirectory note) trash))))))

(ert-deftest my/safety-test-2.1-question-off-still-to-trash ()
  "2.1: with the question turned off nothing is asked, and the note
still goes to the trash."
  (my/safety-test--with-note note
    (let ((my/confirm-deletion 'never))
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (_) (error "Asked although the question is off"))))
        (my/denote-delete-note))
      (should-not (file-exists-p note))
      (should (file-exists-p (expand-file-name (file-name-nondirectory note) trash))))))

;; ============================================================
;; 1.5: THE PUBLISH COMMAND ITSELF
;; ============================================================

(defmacro my/safety-test--publishing (remote &rest body)
  "Run BODY with one site \"s\" uploading to REMOTE, nothing run for real.
`started' holds the options `my/blog--start' was given, `uploaded' is
non-nil once `my/blog--build-and-upload' was called."
  (declare (indent 1))
  `(let ((my/blog-sites (list (list "s" :directory "/tmp/s/" :remote ,remote)))
         (started nil)
         (uploaded nil))
     (cl-letf (((symbol-function 'my/blog--check-program) #'ignore)
               ((symbol-function 'my/blog--sync-templates) #'ignore)
               ((symbol-function 'my/blog--start)
                (lambda (_site options) (setq started options)))
               ((symbol-function 'my/blog--build-and-upload)
                (lambda (&rest _) (setq uploaded t))))
       ,@body)))

(ert-deftest my/safety-test-1.5-publish-refuses-before-export ()
  "1.5, F2: the publish command refuses a home folder before exporting."
  (my/safety-test--publishing "user@server:"
    (should-error (my/blog-publish "s") :type 'user-error)
    (should-not started)
    (should-not uploaded)))

(ert-deftest my/safety-test-1.5-question-names-and-warns ()
  "1.5, F2: the question names site and server and says what the
upload replaces; answering no uploads nothing, yes uploads."
  (my/safety-test--publishing "user@server:/var/www/s/"
    (my/blog-publish "s")
    (should started)
    (let ((prompt nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (p) (setq prompt p) nil)))
        (funcall (plist-get started :on-done) t))
      (should (string-match-p "\\_<s\\_>" prompt))
      (should (string-match-p (regexp-quote "user@server:/var/www/s/") prompt))
      (should (string-match-p "exact copy" prompt))
      (should-not uploaded)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (funcall (plist-get started :on-done) t))
      (should uploaded))))

;; ============================================================
;; 2.4: LEFTOVERS GO TO THE TRASH ONLY ON t
;; ============================================================

(ert-deftest my/safety-test-2.4-leftovers-only-on-consent ()
  "2.4: an old file left beside its new copy is trashed only when the
answer is t; k keeps it."
  (let* ((old (expand-file-name "notes-root.eld" user-emacs-directory))
         (new (my/var-file "notes-root.eld"))
         (trash (make-temp-file "mypks-trash-" t))
         (trash-directory trash)
         (my/host--reports nil))
    (make-directory (file-name-directory new) t)
    (with-temp-file old (insert "old"))
    (with-temp-file new (insert "new"))
    (cl-letf (((symbol-function 'my/notes-report) #'ignore))
      (my/var--setup)
      (let* ((report (seq-find (lambda (r) (string-prefix-p "Old files left" (nth 1 r)))
                               my/host--reports))
             (then (nth 4 report)))
        (should report)
        (funcall then ?k)
        (should (file-exists-p old))
        (funcall then ?t)
        (should-not (file-exists-p old))
        (should (file-exists-p (expand-file-name "notes-root.eld" trash)))
        (should (file-exists-p new))))
    (delete-directory trash t)))

;; ============================================================
;; 1.1-1.4, 1.6: WHAT A SITE TAKES, AND WHAT LEAVES WITH IT
;; ============================================================

(defconst my/safety-test--server "user@server:/var/www/s/"
  "A `:remote' for a site with a server; nothing is uploaded to it.")

(defmacro my/safety-test--with-site (remote &rest body)
  "Run BODY with a notes tree and one site \"s\" whose `:remote' is REMOTE.
The site's one section, posts, takes the notes with the keyword blog
from the silos pks and docu.  Binds `root' (the notes: the silos
journal, pks and docu of `my/silos', the folders inbox and misc),
`site' (the Hugo folder, with a hugo.toml) and `posts' (its
content/posts/)."
  (declare (indent 1))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-notes-" t)))
          (site (file-name-as-directory (make-temp-file "mypks-site-" t)))
          (posts (expand-file-name "content/posts/" site))
          (my-notes-dir root)
          (my/blog-sites
           (list (list "s" :directory site :remote ,remote
                       :sections (list (list "posts" :keyword "blog"
                                             :silos (list "pks" "docu"))))))
          (my/blog-extra-files-file (expand-file-name "extra-files.eld" site))
          (my/blog--extra-cache nil)
          (my/blog--foreign-index-cache nil)
          (my/blog--jobs nil)
          (inhibit-message t))
     (dolist (dir '("journal" "pks" "docu" "inbox" "misc"))
       (make-directory (expand-file-name dir root)))
     (with-temp-file (expand-file-name "hugo.toml" site) (insert "title = 'test'\n"))
     (unwind-protect
         (progn ,@body)
       (dolist (buf (buffer-list))
         (let ((file (buffer-file-name buf)))
           (when (and file (string-prefix-p root file))
             (with-current-buffer buf (set-buffer-modified-p nil))
             (kill-buffer buf))))
       (delete-directory root t)
       (delete-directory site t))))

(defun my/safety-test--note (dir id title &optional keywords body)
  "Write a Denote note titled TITLE with ID and KEYWORDS in DIR; return it.
DIR is relative to `my-notes-dir'; BODY follows the front matter."
  (let ((file (expand-file-name
               (format "%s--%s%s.org" id (downcase title)
                       (if keywords (concat "__" (string-join keywords "_")) ""))
               (expand-file-name dir my-notes-dir))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (format "#+title:      %s\n#+identifier: %s\n\n%s" title id (or body "Text.\n"))))
    file))

(defun my/safety-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my/safety-test--sites (remote silos keyword)
  "Return a `my/blog-sites' of one site with REMOTE and one section.
The section takes notes with KEYWORD from SILOS."
  (list (list "s" :directory "/tmp/s/" :remote remote
              :sections (list (list "posts" :keyword keyword :silos silos)))))

;; 1.1: keyword AND silo
;; ------------------------------------------------------------

(ert-deftest my/safety-test-1.1-keyword-and-silo-both-needed ()
  "1.1: a site takes the notes that carry the section's keyword and lie
in one of its silos -- not a note with the word only in its title, a
keyword merely like it, the keyword in another silo or folder, or a
copy in a dot folder."
  (my/safety-test--with-site nil
    (let ((kant (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")))
          (hegel (my/safety-test--note "docu" "20261023T100100" "Hegel" '("blog" "logic"))))
      (my/safety-test--note "pks" "20261023T100200" "Blog" nil)
      (my/safety-test--note "pks" "20261023T100300" "Fichte" '("blogs"))
      (my/safety-test--note "journal" "20261023T100400" "Day" '("blog"))
      (my/safety-test--note "inbox" "20261023T100500" "Draft" '("blog"))
      (my/safety-test--note "misc" "20261023T100600" "Loose" '("blog"))
      (my/safety-test--note "pks/.snapshots/1" "20261023T100000" "Kant" '("blog"))
      (let ((site (my/blog--site "s")))
        (should (equal (my/blog--candidates site) (list kant hegel)))
        (should (equal (mapcar #'car (plist-get (my/blog--plan site) :ready))
                       (list kant hegel)))))))

(ert-deftest my/safety-test-1.1-other-silo-on-no-site ()
  "1.1: the keyword in a silo or folder the section does not take puts a
note on no site.  Asked of one note -- the question behind exporting the
current note and the export after saving, which do not go through the
list of candidates and its silos."
  (my/safety-test--with-site nil
    (let ((site (my/blog--site "s")))
      (dolist (dir '("journal" "inbox" "misc"))
        (let ((note (my/safety-test--note dir "20261023T100400" "Day" '("blog"))))
          (should-not (my/blog--sections-of site note))
          (should-not (my/blog--sites-of note))))
      (should (equal (my/blog--sections-of
                      site (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")))
                     '("posts"))))))

(ert-deftest my/safety-test-1.1-include-of-other-note-refused ()
  "1.1: a note that pulls a note not on the site into itself with
#+INCLUDE is refused whole: the other note's text would be on the page."
  (my/safety-test--with-site nil
    (my/safety-test--note "journal" "20261023T100400" "Day" nil "Private text.\n")
    (let* ((kant (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")
                                       "#+INCLUDE: \"../journal/20261023T100400--day.org\"\n"))
           (plan (my/blog--plan (my/blog--site "s"))))
      (should-not (plist-get plan :ready))
      (should (equal (mapcar #'car (plist-get plan :refused)) (list kant)))
      (should (string-match-p "includes a note not on this site"
                              (nth 1 (car (plist-get plan :refused))))))))

;; 1.2: a site with a server -- checked before every command
;; ------------------------------------------------------------

(ert-deftest my/safety-test-1.2-server-site-refuses-private-silos ()
  "1.2: a section of a site with a server that takes notes from journal
or inbox stops the configuration check; the same section on a site
without a server passes it."
  (dolist (silos '(("journal") ("inbox") ("pks" "journal")))
    (let ((my/blog-sites (my/safety-test--sites my/safety-test--server silos "blog")))
      (should-error (my/blog--check-config) :type 'user-error))
    (let ((my/blog-sites (my/safety-test--sites nil silos "blog")))
      (my/blog--check-config))))

(ert-deftest my/safety-test-1.2-silo-marked-private-counts ()
  "1.2: a silo marked :private in `my/silos' is refused like journal."
  (let ((my/blog-sites (my/safety-test--sites my/safety-test--server '("docu") "blog")))
    (my/blog--check-config)
    (let ((my/silos (mapcar (lambda (silo)
                              (if (eq (car silo) 'docu)
                                  (cons 'docu (plist-put (copy-sequence (cdr silo)) :private t))
                                silo))
                            my/silos)))
      (should-error (my/blog--check-config) :type 'user-error))))

(ert-deftest my/safety-test-1.2-silo-name-as-keyword-refused ()
  "1.2: on a site with a server, a silo's name as a section keyword
stops the configuration check: it would select the whole silo."
  (dolist (keyword '("pks" "journal" "inbox"))
    (let ((my/blog-sites (my/safety-test--sites my/safety-test--server '("pks") keyword)))
      (should-error (my/blog--check-config) :type 'user-error))
    (let ((my/blog-sites (my/safety-test--sites nil '("pks") keyword)))
      (my/blog--check-config))))

(ert-deftest my/safety-test-1.2-registry-silo-as-keyword-refused ()
  "1.2: a silo of `my/silos' that no site names is a silo all the same:
its key, its folder and its `:keyword' are refused as keywords on a site
with a server -- a disabled silo's too (found 2026-10-23g: docu
passed)."
  (let ((my/silos (append (mapcar (lambda (silo)
                                    (if (eq (car silo) 'docu)
                                        (cons 'docu (plist-put (copy-sequence (cdr silo))
                                                               :keyword "docs"))
                                      silo))
                                  my/silos)
                          (list (list 'archive :directory "old-notes/" :keyword "archived"
                                      :disabled t)))))
    (dolist (keyword '("docu" "docs" "archive" "old-notes" "archived"))
      (let ((my/blog-sites (my/safety-test--sites my/safety-test--server '("pks") keyword)))
        (should-error (my/blog--check-config) :type 'user-error))
      (let ((my/blog-sites (my/safety-test--sites nil '("pks") keyword)))
        (my/blog--check-config)))))

(ert-deftest my/safety-test-1.2-refused-before-anything-is-written ()
  "1.2: an export of a site breaking the rule stops before a page is
written."
  (my/safety-test--with-site my/safety-test--server
    (my/safety-test--note "journal" "20261023T100400" "Day" '("blog"))
    (setf (plist-get (cdr (car (my/blog--sections (my/blog--site "s")))) :silos)
          (list "pks" "journal"))
    (should-error (my/blog-export-all "s") :type 'user-error)
    (should-not (file-exists-p posts))
    (should-not (file-exists-p (my/blog--state-path (my/blog--site "s"))))))

;; 1.3: files placed by hand
;; ------------------------------------------------------------

(ert-deftest my/safety-test-1.3-placed-private-file-refused-on-server ()
  "1.3: a file of journal or inbox placed on a site by hand is refused
once the site has a server; a file of another folder is not.  Without
a server all three are on the site."
  (my/safety-test--with-site nil
    (let ((day (my/safety-test--note "journal" "20261023T100400" "Day"))
          (draft (my/safety-test--note "inbox" "20261023T100500" "Draft"))
          (loose (my/safety-test--note "misc" "20261023T100600" "Loose")))
      (dolist (file (list day draft loose))
        (my/blog-place-file file '("s") "posts"))
      (should (equal (mapcar #'car (plist-get (my/blog--plan (my/blog--site "s")) :ready))
                     (list day draft loose)))
      (setf (plist-get (cdr (my/blog--site "s")) :remote) my/safety-test--server)
      (let ((plan (my/blog--plan (my/blog--site "s"))))
        (should (equal (mapcar #'car (plist-get plan :ready)) (list loose)))
        (should (equal (mapcar #'car (plist-get plan :refused)) (list day draft)))
        (dolist (refused (plist-get plan :refused))
          (should (string-match-p "private silo" (nth 1 refused))))))))

;; 1.4: what a page says about notes that are not published
;; ------------------------------------------------------------

(ert-deftest my/safety-test-1.4-link-to-unpublished-note-is-its-text ()
  "1.4: a `denote:' link to a note not on the site is written as its
description and nothing else -- empty without one; a link to a page of
the site becomes a link to it."
  (let* ((targets (make-hash-table :test #'equal))
         (export (progn (puthash "20261023T100000" '("posts" "kant" nil) targets)
                        (my/blog--link-export-function targets))))
    (should (equal (funcall export "20261023T110000" "the other one" 'md) "the other one"))
    (should (equal (funcall export "20261023T110000" nil 'md) ""))
    (should (equal (funcall export "20261023T110000::*Logic" "his logic" 'md) "his logic"))
    (should (equal (funcall export "20261023T100000" "Kant" 'html) "Kant"))
    (should (equal (funcall export "20261023T100000::#ethics" "Kant" 'md)
                   "[Kant](/posts/kant/#ethics)"))))

(ert-deftest my/safety-test-1.4-page-names-no-unpublished-note ()
  "1.4: the page ox-hugo writes for a note says nothing of the notes it
links to that are not on the site -- no identifier, file name, title
other than the link's own words, folder or link type.  Denote's own
export of its links writes the file name; the site's replaces it."
  (skip-unless (require 'ox-hugo nil t))
  (my/safety-test--with-site my/safety-test--server
    (my/safety-test--note "pks" "20261023T110000" "Hegel" nil "* Logic\nText.\n")
    (my/safety-test--note "journal" "20261023T120000" "Day" nil)
    (my/safety-test--note "pks" "20261023T130000" "Fichte" '("blog"))
    (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")
                          (concat "See [[denote:20261023T110000][the other one]], "
                                  "[[denote:20261023T110000::*Logic][his logic]], "
                                  "[[denote:20261023T110000]], "
                                  "[[denote:20261023T120000][that day]] "
                                  "and [[denote:20261023T130000][Fichte]].\n"))
    (my/blog--start "s" '(:write t))
    (let ((page (my/safety-test--read (expand-file-name "kant.md" posts)))
          (case-fold-search t))
      (should (string-match-p (regexp-quote "See the other one, his logic, , that day and [Fichte](/posts/fichte/).")
                              page))
      (dolist (leak (list "20261023T110000" "20261023T120000" "hegel" "journal"
                          "denote" ".org" (directory-file-name root)))
        (should-not (string-match-p (regexp-quote leak) page))))))

(ert-deftest my/safety-test-1.4-file-link-to-note-is-its-text ()
  "1.4: a `file:' link to a note -- Org, Markdown, text, encrypted -- is
exported like a `denote:' link to the identifier in its name: the
description, or a link to the note's page; another file is left to
ox-hugo (found 2026-10-23g: ox-hugo wrote the file name)."
  (let* ((targets (make-hash-table :test #'equal))
         (export (progn (puthash "20261023T100000" '("posts" "kant" nil) targets)
                        (my/blog--file-link-export-function targets))))
    (dolist (path '("../pks/20261023T110000--hegel.org" "20261023T110000--hegel.md"
                    "/n/pks/20261023T110000--hegel.txt" "20261023T110000--hegel.org.gpg"
                    "../misc/plain.org"))
      (should (equal (funcall export path "the other one" 'md nil) "the other one"))
      (should (equal (funcall export path nil 'md nil) "")))
    (should (equal (funcall export "20261023T100000--kant__blog.org" "Kant" 'md nil)
                   "[Kant](/posts/kant/)"))
    (dolist (path '("../attachments/20261023T110000--hegel-0.png" "paper.pdf"))
      (should-not (funcall export path "x" 'md nil)))))

(ert-deftest my/safety-test-1.4-page-file-links-name-no-note ()
  "1.4: the page ox-hugo writes for a note with `file:' links to notes
off the site names none of them, asks nothing -- a heading search in a
missing heading made Org offer to create it in the other note -- and
leaves those notes as they were; a `file:' link to a published note
links its page; an image and a PDF are still copied and linked."
  (skip-unless (require 'ox-hugo nil t))
  (my/safety-test--with-site my/safety-test--server
    (let ((hegel (my/safety-test--note "pks" "20261023T110000" "Hegel" nil)))
      (make-directory (expand-file-name "attachments" root))
      (dolist (file '("attachments/paper.pdf" "attachments/20261023T100000--kant-0.png"
                      "pks/20261023T120000--fichte.md" "pks/20261023T130000--schelling.txt"))
        (with-temp-file (expand-file-name file root) (insert "Private.\n")))
      (my/safety-test--note "pks" "20261023T140000" "Spinoza" '("blog"))
      (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")
                            (concat "A [[file:20261023T110000--hegel.org::*Missing][one]], "
                                    "B [[file:20261023T120000--fichte.md][two]], "
                                    "C [[file:20261023T130000--schelling.txt][three]], "
                                    "D [[file:20261023T140000--spinoza__blog.org][four]], "
                                    "E [[file:../attachments/paper.pdf][paper]].\n\n"
                                    "[[file:../attachments/20261023T100000--kant-0.png]]\n"))
      (let ((text (my/safety-test--read hegel)))
        (cl-letf (((symbol-function 'yes-or-no-p)
                   (lambda (prompt) (error "Asked: %s" prompt))))
          (my/blog--start "s" '(:write t)))
        (should (equal (my/safety-test--read hegel) text)))
      (let ((page (my/safety-test--read (expand-file-name "kant.md" posts))))
        (should (string-match-p (regexp-quote "A one, B two, C three, D [four](/posts/spinoza/), E [paper](/ox-hugo/paper.pdf).")
                                page))
        (should (string-match-p (regexp-quote "/ox-hugo/20261023T100000--kant-0.png") page))
        (dolist (leak '("20261023T110000" "20261023T120000" "20261023T130000" "relref"))
          (should-not (string-match-p (regexp-quote leak) page))))
      (should (file-exists-p (expand-file-name "static/ox-hugo/paper.pdf" site))))))

(ert-deftest my/safety-test-1.4-page-redone-when-linked-note-leaves ()
  "1.4: when a note leaves the site, the pages linking to it -- by a
`denote:' or a `file:' link -- are exported again, so that the link
becomes its text; otherwise they would keep a link naming the page of
a note no longer published."
  (my/safety-test--with-site nil
    (let ((spinoza (my/safety-test--note "pks" "20261023T140000" "Spinoza" '("blog")))
          (exported '()))
      (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog")
                            "See [[denote:20261023T140000][him]].\n")
      (my/safety-test--note "pks" "20261023T110000" "Hegel" '("blog")
                            "See [[file:20261023T140000--spinoza__blog.org][him]].\n")
      (cl-letf (((symbol-function 'my/blog--require-ox-hugo) #'ignore)
                ((symbol-function 'my/blog--export-file)
                 (lambda (site file section slug _targets)
                   (push (file-name-nondirectory file) exported)
                   (with-temp-file (my/blog--page-file site section slug) (insert "page")))))
        (make-directory posts t)
        (my/blog--start "s" '(:write t :quiet t))
        (setq exported '())
        (rename-file spinoza (replace-regexp-in-string "__blog" "" spinoza))
        (my/blog--start "s" '(:write t :quiet t))
        (should (equal (sort exported #'string<)
                       '("20261023T100000--kant__blog.org" "20261023T110000--hegel__blog.org")))))))

(ert-deftest my/safety-test-1.4-backlinks-name-only-pages ()
  "1.4: the backlinks the site's pages show name only pages of the site:
not a note off the site, nor a note of the site that was refused, that
links to a published one."
  (my/safety-test--with-site nil
    (my/safety-test--note "journal" "20261023T120000" "Day" nil)
    (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog"))
    (my/safety-test--note "pks" "20261023T130000" "Fichte" '("blog")
                          "After [[denote:20261023T100000][Kant]].\n")
    (my/safety-test--note "pks" "20261023T110000" "Hegel" nil
                          "Against [[denote:20261023T100000][Kant]].\n")
    (my/safety-test--note "pks" "20261023T140000" "Schelling" '("blog")
                          (concat "#+INCLUDE: \"../journal/20261023T120000--day.org\"\n"
                                  "Like [[denote:20261023T100000][Kant]].\n"))
    (let ((plan (my/blog--plan (my/blog--site "s"))))
      (my/blog--write-backlinks (my/blog--site "s") plan)
      (should (equal (my/safety-test--read (expand-file-name "data/blog_backlinks.json" site))
                     "{\"/posts/kant\":[\"/posts/fichte\"]}")))))

;; 1.6: unpublishing
;; ------------------------------------------------------------

(defmacro my/safety-test--pruning (&rest body)
  "Run BODY in `my/safety-test--with-site's notes and site, set up for pruning.
Kant is published, Hegel was and is no longer (its keyword is gone):
posts/ holds kant.md, hegel.md, the hand-written _index.md and a
stray hegel.org; content/other/ a page of no section.  ox-hugo is not
needed: an export writes a stand-in page.  Binds `hegel' (the note),
`pages' (the files of the site to check), `asked' (the questions asked)
and `answer' (the answer given, nil at first)."
  (declare (indent 0))
  `(let ((hegel (my/safety-test--note "pks" "20261023T110000" "Hegel" nil))
         (asked '())
         (answer nil))
     (my/safety-test--note "pks" "20261023T100000" "Kant" '("blog"))
     (make-directory posts t)
     (make-directory (expand-file-name "content/other" site))
     (dolist (page '("content/posts/kant.md" "content/posts/hegel.md"
                     "content/posts/_index.md" "content/posts/hegel.org"
                     "content/other/hegel.md"))
       (with-temp-file (expand-file-name page site) (insert "page")))
     (cl-letf (((symbol-function 'my/blog--require-ox-hugo) #'ignore)
               ((symbol-function 'my/blog--export-file)
                (lambda (site _file section slug _targets)
                  (with-temp-file (my/blog--page-file site section slug) (insert "page"))))
               ((symbol-function 'yes-or-no-p)
                (lambda (prompt) (push prompt asked) answer)))
       ,@body)))

(defun my/safety-test--pages (site)
  "Return the files under the content/ of SITE's folder, relative to it."
  (let ((content (expand-file-name "content/" site)))
    (sort (mapcar (lambda (f) (file-relative-name f content))
                  (directory-files-recursively content ""))
          #'string<)))

(ert-deftest my/safety-test-1.6-unpublishing-removes-only-pages ()
  "1.6: on a site without a server the page of a note that left the site
is removed without a question; the note itself, the hand-written
_index.md, a file that is no page and the pages outside the site's
sections stay."
  (my/safety-test--with-site nil
    (my/safety-test--pruning
      (let ((text (my/safety-test--read hegel)))
        (my/blog--start "s" '(:write t :quiet t))
        (should-not asked)
        (should (equal (my/safety-test--pages site)
                       '("other/hegel.md" "posts/_index.md" "posts/hegel.org" "posts/kant.md")))
        (should (equal (my/safety-test--read hegel) text))))))

(ert-deftest my/safety-test-1.6-server-site-asks-first ()
  "1.6: on a site with a server, an export started by hand asks before
removing a page; no keeps it, yes removes it."
  (my/safety-test--with-site my/safety-test--server
    (my/safety-test--pruning
      (my/blog-export-all "s")
      (should (= 1 (length asked)))
      (should (string-match-p "Remove 1 page" (car asked)))
      (should (file-exists-p (expand-file-name "hegel.md" posts)))
      (setq answer t)
      (my/blog-export-all "s")
      (should-not (file-exists-p (expand-file-name "hegel.md" posts)))
      (should (file-exists-p (expand-file-name "_index.md" posts)))
      (should (file-exists-p hegel)))))

(ert-deftest my/safety-test-1.6-server-site-background-removes-nothing ()
  "1.6: on a site with a server, an export in the background -- the
one after saving a note, or at start-up -- neither asks nor removes."
  (my/safety-test--with-site my/safety-test--server
    (my/safety-test--pruning
      (setq answer t)
      (my/blog--start "s" '(:write t :quiet t))
      (should-not asked)
      (should (file-exists-p (expand-file-name "hegel.md" posts))))))

(provide 'test-safety)
;;; test-safety.el ends here
