;;; test-obsidian-import.el --- ERT tests for 42-obsidian-import and its script -*- lexical-binding: t; -*-

;; Tests: 42-obsidian-import

;;; Commentary:

;; 42-obsidian-import.el runs tools/obsidian_import.py, which merges
;; notes written in Obsidian into the journal, writes inbox notes,
;; copies attachments and moves each markdown file out of the vault's
;; inbox; the module saves the note buffers before the run and reverts
;; the files written after it.  The tenth module of TESTING.org, *Every
;; module tested*, part 3.
;;
;; Two halves: the script run directly, on a vault and a notes folder in
;; a temporary folder (what it writes, keeps, moves and skips), and the
;; module's own part -- the checks before a run, which buffers are saved
;; and reverted, a whole run through the commands.  With the real
;; pandoc and PyYAML, the ones the script uses: a test skips without
;; them (a missing program), and the workflow installs both.  One test
;; puts a failing stand-in for pandoc first on PATH.
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-obsidian-import.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.  Needs python3, PyYAML and
;; pandoc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "42-obsidian-import")

;; ============================================================
;; FIXTURE
;; ============================================================

(defconst my/obs-test--script
  (expand-file-name "tools/obsidian_import.py" my/test-repo)
  "The import script of this repository, not ~/.emacs.d's.")

(defvar my/obs-test--tools-present 'unknown
  "Whether python3 with PyYAML, and pandoc, are present; checked once.")

(defun my/obs-test--tools-p ()
  "Return non-nil when the script can run here: python3, PyYAML, pandoc."
  (when (eq my/obs-test--tools-present 'unknown)
    (setq my/obs-test--tools-present
          (and (executable-find "python3")
               (executable-find "pandoc")
               (eql 0 (call-process "python3" nil nil nil "-c" "import yaml")))))
  my/obs-test--tools-present)

(defmacro my/obs-test--with-tree (&rest body)
  "Run BODY with a vault and a notes folder in a fresh temporary folder.
Binds `root', `vault', `inbox' (the vault folder the script reads),
`imported', `notes', `journal'.  The journal silo exists; the settle
time is zero, so files just written are imported."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "mypks-obs-" t)))
          (vault (file-name-as-directory (expand-file-name "vault" root)))
          (inbox (file-name-as-directory (expand-file-name "10 Emacs Inbox" vault)))
          (imported (file-name-as-directory (expand-file-name "Imported2Emacs/2026" vault)))
          (notes (file-name-as-directory (expand-file-name "notes" root)))
          (journal (file-name-as-directory (expand-file-name "journal" notes)))
          (my-notes-dir notes)
          (my/obsidian-vault-directory vault)
          (my/obsidian-import-script my/obs-test--script)
          (my/obsidian-python "python3")
          (my/obsidian-import-settle 0)
          (my/obsidian-import--touched-file nil)
          (inhibit-message t))
     (make-directory inbox t)
     (make-directory journal t)
     (unwind-protect
         (progn ,@body)
       (let ((report (get-buffer my/obsidian-import-buffer)))
         (when report
           (dolist (proc (process-list))
             (when (eq (process-buffer proc) report) (delete-process proc)))
           (kill-buffer report)))
       (dolist (b (buffer-list))
         (let ((f (buffer-file-name b)))
           (when (and f (string-prefix-p root (file-truename f)))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory root t))))

(defun my/obs-test--write (file text)
  "Write TEXT to FILE, creating its folder; return FILE."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region text nil file nil 'silent))
  file)

(defun my/obs-test--read (file)
  "Return the contents of FILE."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defun my/obs-test--script-run (vault notes &rest args)
  "Run the import script on VAULT and NOTES with ARGS; return (EXIT . OUTPUT).
Started in a temporary folder (TESTING.org, rule 8); EXIT is the exit
status the process returned (rule 14)."
  (let ((cwd (file-name-as-directory (make-temp-file "mypks-obs-cwd-" t))))
    (unwind-protect
        (with-temp-buffer
          (let* ((default-directory cwd)
                 (code (apply #'call-process "python3" nil t nil my/obs-test--script
                              "--vault" vault "--notes" notes args)))
            (cons code (buffer-string))))
      (delete-directory cwd t))))

(defun my/obs-test--count (regexp text)
  "Return how many times REGEXP matches in TEXT."
  (let ((n 0) (start 0))
    (while (string-match regexp text start)
      (setq n (1+ n) start (match-end 0)))
    n))

(defun my/obs-test--lines-in-order-p (old new)
  "Return non-nil when every non-empty line of OLD is in NEW, in order."
  (let ((pos 0))
    (cl-every (lambda (line)
                (let ((at (string-search (concat line "\n") new pos)))
                  (when at (setq pos (+ at (length line))))))
              (split-string old "\n" t))))

(defun my/obs-test--files (dir)
  "Return the regular files under DIR, or nil when DIR does not exist."
  (and (file-directory-p dir)
       (directory-files-recursively dir "" nil)))

(defun my/obs-test--run-command (command &optional after-start)
  "Call COMMAND, then AFTER-START, then wait for the run's sentinel.
Return non-nil when the sentinel ran within two minutes."
  (let* ((done nil)
         (mark (lambda (&rest _) (setq done t))))
    (advice-add 'my/obsidian-import--sentinel :after mark)
    (unwind-protect
        (let ((deadline (+ (float-time) 120)))
          (funcall command)
          (when after-start (funcall after-start))
          (while (and (not done) (< (float-time) deadline))
            (accept-process-output nil 0.1))
          done)
      (advice-remove 'my/obsidian-import--sentinel mark))))

;; ------------------------------------------------------------
;; Sample notes
;; ------------------------------------------------------------

(defconst my/obs-test--daily
  "---\ncreated: 2026-10-20T08:15:00\ndate: 2026-10-20\ntags: [journal]\n---\n# (08:15)\n---\nRano pisałam o Kancie.\n"
  "A daily note as Obsidian's template writes it, for 2026-10-20.")

(defconst my/obs-test--journal-name "20261020T070000--2026-10-20__journal.org"
  "File name of the journal note of 2026-10-20 in the fixtures.")

(defconst my/obs-test--journal-text
  "#+title:      2026-10-20\n#+filetags:   :journal:\n#+identifier: 20261020T070000\n\n* 07:00\nWstałam wcześnie.\n"
  "A journal note written in Emacs, with no imported material yet.")

(defun my/obs-test--daily-file (inbox)
  "Write the daily note of 2026-10-20 into INBOX; return its path."
  (my/obs-test--write (expand-file-name "2026-10-20.md" inbox) my/obs-test--daily))

(defun my/obs-test--journal-file (journal &optional text)
  "Write the journal note of 2026-10-20 (TEXT, or the plain one) into JOURNAL."
  (my/obs-test--write (expand-file-name my/obs-test--journal-name journal)
                      (or text my/obs-test--journal-text)))

(defun my/obs-test--inbox-note (inbox body)
  "Write a non-daily note created 2026-10-20 10:00:00 with BODY into INBOX."
  (my/obs-test--write (expand-file-name "Esej.md" inbox)
                      (concat "---\ncreated: 2026-10-20T10:00:00\ntags: [filozofia]\n---\n"
                              body "\n")))

;; A run that fails midway: the daily note of 2026 imports, then the note
;; of 2025 cannot be moved because a file stands where its year folder
;; would be.  Sources are taken by name, so the daily note goes first.
(defun my/obs-test--midway-failure (vault inbox journal)
  "Set up a run in VAULT that fails on its second note; return its paths.
A plist: :daily (imported first), :late (the note that fails) and
:target (the journal note the first one is merged into)."
  (let ((daily (my/obs-test--daily-file inbox))
        (late (my/obs-test--write (expand-file-name "Stara.md" inbox)
                                  "---\ncreated: 2025-05-01T09:00:00\n---\nStara notatka.\n"))
        (target (my/obs-test--journal-file journal)))
    (my/obs-test--write (expand-file-name "Imported2Emacs/2025" vault) "not a folder\n")
    (list :daily daily :late late :target target)))

;; ============================================================
;; THE SCRIPT: WHAT IT WRITES AND KEEPS
;; ============================================================

(ert-deftest my/obs-test-script-dry-run-writes-nothing ()
  "Without --write nothing is written, copied or moved: the journal note
is byte for byte as it was, no inbox note or attachment exists, the
markdown stays in the vault's inbox, and no touched list is written --
yet the report names what would happen."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((daily (my/obs-test--daily-file inbox))
           (note (my/obs-test--inbox-note inbox "Szkic: ![](pic.png)"))
           (pic (my/obs-test--write (expand-file-name "pic.png" inbox) "PICTURE"))
           (target (my/obs-test--journal-file journal))
           (touched (expand-file-name "touched.txt" root))
           (result (my/obs-test--script-run vault notes "--settle" "0"
                                            "--touched" touched)))
      (should (= 0 (car result)))
      (should (string-match-p "DRY RUN" (cdr result)))
      (should (string-match-p "journal-merge" (cdr result)))
      (should (equal (my/obs-test--read target) my/obs-test--journal-text))
      (should-not (file-exists-p (expand-file-name "inbox" notes)))
      (should-not (file-exists-p (expand-file-name "attachments" notes)))
      (should-not (file-exists-p (expand-file-name "Imported2Emacs" vault)))
      (should (equal (my/obs-test--read daily) my/obs-test--daily))
      (should (file-exists-p note))
      (should (file-exists-p pic))
      (should-not (file-exists-p touched)))))

(ert-deftest my/obs-test-script-merge-keeps-journal-text ()
  "A daily note merged into the journal note of its date keeps every
character of that note in front, and adds one `* Obsidian' subtree with
its source and the entry under a plain time heading."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (let* ((target (my/obs-test--journal-file journal))
           (result (my/obs-test--script-run vault notes "--settle" "0" "--write"))
           (text (my/obs-test--read target)))
      (should (= 0 (car result)))
      (should (string-prefix-p (string-trim-right my/obs-test--journal-text) text))
      (should (= 1 (my/obs-test--count "^\\* Obsidian$" text)))
      (should (string-match-p "^:SOURCE: +10 Emacs Inbox/2026-10-20\\.md$" text))
      (should (string-match-p "^\\*\\* 08:15\nRano pisałam o Kancie\\.$" text))
      ;; One journal note for the date: merged, not a second file.
      (should (equal (directory-files journal nil "\\.org\\'")
                     (list my/obs-test--journal-name))))))

(ert-deftest my/obs-test-script-second-import-joins-obsidian-heading ()
  "A second import into a journal note that already has `* Obsidian'
goes at the end of that subtree, before the next top-level heading;
every line of the note stays, in order, and no second `* Obsidian'
appears."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (let* ((old (concat my/obs-test--journal-text
                        "\n* Obsidian\n:PROPERTIES:\n:SOURCE:      10 Emacs Inbox/earlier.md\n:END:\n\n"
                        "** 06:30\nPierwszy import.\n\n* Wieczór\nKolacja.\n"))
           (target (my/obs-test--journal-file journal old))
           (result (my/obs-test--script-run vault notes "--settle" "0" "--write"))
           (text (my/obs-test--read target)))
      (should (= 0 (car result)))
      (should (= 1 (my/obs-test--count "^\\* Obsidian$" text)))
      (should (my/obs-test--lines-in-order-p old text))
      (let ((first (string-search "Pierwszy import." text))
            (new (string-search "Rano pisałam o Kancie." text))
            (evening (string-search "* Wieczór" text)))
        (should (and first new evening))
        (should (< first new evening)))
      (should (string-suffix-p "* Wieczór\nKolacja.\n" text)))))

(ert-deftest my/obs-test-script-new-journal-file ()
  "A daily note for a date with no journal note makes one, named and
headed the way the journal of this configuration is, with the entry
under `* Obsidian'."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--write (expand-file-name "2026-10-21.md" inbox)
                        (replace-regexp-in-string "2026-10-20" "2026-10-21" my/obs-test--daily))
    (let* ((result (my/obs-test--script-run vault notes "--settle" "0" "--write"))
           (target (expand-file-name "20261021T081500--2026-10-21__journal.org" journal)))
      (should (= 0 (car result)))
      (should (file-exists-p target))
      (let ((text (my/obs-test--read target)))
        (should (string-prefix-p "#+title:      2026-10-21\n" text))
        (should (string-match-p "^#\\+filetags: +:journal:$" text))
        (should (string-match-p "^#\\+identifier: 20261021T081500$" text))
        (should (string-match-p "^\\* Obsidian$" text))))))

(ert-deftest my/obs-test-script-source-moved-unchanged ()
  "After an import the markdown file is in Imported2Emacs/<year>, with
the content it had, and no longer in the vault's inbox -- which is
what keeps a second run from importing it again."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let ((daily (my/obs-test--daily-file inbox)))
      (my/obs-test--journal-file journal)
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should-not (file-exists-p daily))
      (should (equal (my/obs-test--read (expand-file-name "2026-10-20.md" imported))
                     my/obs-test--daily))
      (let ((again (my/obs-test--script-run vault notes "--settle" "0" "--write")))
        (should (= 0 (car again)))
        (should (string-match-p "Nothing to import" (cdr again)))))))

(ert-deftest my/obs-test-script-moved-file-never-overwritten ()
  "A file of the same name already in Imported2Emacs/<year> stays as it
was; the one just imported is put beside it under a numbered name."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (my/obs-test--journal-file journal)
    (let ((older (my/obs-test--write (expand-file-name "2026-10-20.md" imported)
                                     "older import\n")))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (equal (my/obs-test--read older) "older import\n"))
      (should (equal (my/obs-test--read (expand-file-name "2026-10-20-2.md" imported))
                     my/obs-test--daily)))))

(ert-deftest my/obs-test-script-attachment-copied-not-moved ()
  "An image a note links to is copied into the attachments folder under
the note's identifier and linked there; the image in the vault stays,
so links in the vault keep working."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--inbox-note inbox "Szkic: ![](pic.png)")
    (let ((pic (my/obs-test--write (expand-file-name "pic.png" inbox) "PICTURE"))
          (copy (expand-file-name "attachments/20261020T100000--pic.png" notes)))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (equal (my/obs-test--read pic) "PICTURE"))
      (should (equal (my/obs-test--read copy) "PICTURE"))
      (let ((note (car (directory-files (expand-file-name "inbox" notes) t "\\.org\\'"))))
        (should note)
        (should (string-search (concat "[[file:" copy "]]") (my/obs-test--read note)))))))

(ert-deftest my/obs-test-script-attachment-never-overwritten ()
  "An attachment already named for the identifier a new note would get
-- left by a note deleted since -- stays as it was, and the new note
links to a copy of its own image, not to that file.  Two safeguards:
identifiers already used by any file are not given again, and a copy
never replaces an existing file."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--inbox-note inbox "Szkic: ![](pic.png)")
    (my/obs-test--write (expand-file-name "pic.png" inbox) "NEW PICTURE")
    (let ((old (my/obs-test--write
                (expand-file-name "attachments/20261020T100000--pic.png" notes)
                "OLD PICTURE")))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (equal (my/obs-test--read old) "OLD PICTURE"))
      (let* ((note (car (directory-files (expand-file-name "inbox" notes) t "\\.org\\'")))
             (text (and note (my/obs-test--read note))))
        (should text)
        (should (string-match "\\[\\[file:\\([^]]+\\)\\]\\]" text))
        (should (equal (my/obs-test--read (expand-file-name (match-string 1 text)))
                       "NEW PICTURE"))))))

(ert-deftest my/obs-test-script-identifier-not-reused ()
  "A new note never takes an identifier another note already has --
an Org note or a Markdown one (40-markdown) -- nor one in a notes
folder that lies under a dot folder: it moves on by seconds."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((notes (file-name-as-directory (expand-file-name ".sync/notes" root)))
           (pks (expand-file-name "pks" notes)))
      (make-directory (expand-file-name "journal" notes) t)
      (my/obs-test--write (expand-file-name "20261020T100000--kant__filozofia.org" pks) "Kant\n")
      (my/obs-test--write (expand-file-name "20261020T100001--hume__filozofia.md" pks) "Hume\n")
      (my/obs-test--inbox-note inbox "Szkic.")
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (equal (directory-files (expand-file-name "inbox" notes) nil "\\.org\\'")
                     '("20261020T100002--esej__filozofia.org"))))))

;; ============================================================
;; THE SCRIPT: WHAT IT LEAVES ALONE
;; ============================================================

(ert-deftest my/obs-test-script-young-file-left ()
  "A file modified within the settle time is neither imported nor moved:
the phone may still be writing it."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let ((daily (my/obs-test--daily-file inbox))
          (target (my/obs-test--journal-file journal)))
      (let ((result (my/obs-test--script-run vault notes "--settle" "3600" "--write")))
        (should (= 0 (car result)))
        (should (string-match-p "Nothing to import" (cdr result))))
      (should (equal (my/obs-test--read daily) my/obs-test--daily))
      (should (equal (my/obs-test--read target) my/obs-test--journal-text))
      (should-not (file-exists-p (expand-file-name "Imported2Emacs" vault))))))

(ert-deftest my/obs-test-script-conflicts-and-hidden-left ()
  "Syncthing's conflict copies and files in dot folders inside the inbox
are neither imported nor moved; a vault that itself lies under a dot
folder is still read."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((vault (file-name-as-directory (expand-file-name ".sync/vault" root)))
           (inbox (file-name-as-directory (expand-file-name "10 Emacs Inbox" vault)))
           (conflict (my/obs-test--write
                      (expand-file-name "2026-10-20.sync-conflict-20261020-081500-ABCDEFG.md" inbox)
                      my/obs-test--daily))
           (hidden (my/obs-test--write (expand-file-name ".trash/Stara.md" inbox) "stara\n"))
           (daily (my/obs-test--daily-file inbox)))
      (my/obs-test--journal-file journal)
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (file-exists-p conflict))
      (should (file-exists-p hidden))
      (should-not (file-exists-p daily))
      (should (equal (directory-files (expand-file-name "Imported2Emacs/2026" vault)
                                      nil "\\.md\\'")
                     '("2026-10-20.md")))
      (should-not (file-exists-p (expand-file-name "inbox" notes))))))

(ert-deftest my/obs-test-script-pandoc-failure-keeps-source ()
  "When pandoc fails on a note the note stays in the vault's inbox and
nothing is written for it; the report names the failure, and the run
ends with status 2: through, with notes not imported (until 2026-10-24
it ended with 0, and the module said the import was done)."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((bin (expand-file-name "bin" root))
           (pandoc (my/obs-test--write
                    (expand-file-name "pandoc" bin)
                    "#!/bin/sh\n[ \"$1\" = --version ] && exit 0\ncat >/dev/null\necho 'stand-in failure' >&2\nexit 3\n"))
           (process-environment (cons (concat "PATH=" bin path-separator (getenv "PATH"))
                                      process-environment))
           (daily (my/obs-test--daily-file inbox))
           (target (my/obs-test--journal-file journal)))
      (set-file-modes pandoc #o755)
      (let ((result (my/obs-test--script-run vault notes "--settle" "0" "--write")))
        (should (= 2 (car result)))
        (should (string-match-p "pandoc failed: stand-in failure" (cdr result))))
      (should (equal (my/obs-test--read daily) my/obs-test--daily))
      (should (equal (my/obs-test--read target) my/obs-test--journal-text))
      (should-not (file-exists-p (expand-file-name "Imported2Emacs" vault))))))

(ert-deftest my/obs-test-script-broken-yaml-left-in-inbox ()
  "A note whose front matter is not valid YAML is not imported: it stays
in the inbox, unchanged, nothing is written for it, the report names
it, and the run ends with status 2.  A good note beside it is imported."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let ((broken (my/obs-test--write (expand-file-name "Zepsuta.md" inbox)
                                      "---\ncreated: [2026-10-20\ntags: [a\n---\nTreść.\n")))
      (my/obs-test--inbox-note inbox "Dobra.")
      (let ((result (my/obs-test--script-run vault notes "--settle" "0" "--write")))
        (should (= 2 (car result)))
        (should (string-match-p "Zepsuta.md: front matter is not valid YAML" (cdr result))))
      (should (equal (my/obs-test--read broken)
                     "---\ncreated: [2026-10-20\ntags: [a\n---\nTreść.\n"))
      (should (equal (directory-files (expand-file-name "inbox" notes) nil "\\.org\\'")
                     '("20261020T100000--esej__filozofia.org"))))))

(ert-deftest my/obs-test-script-same-image-name-two-images ()
  "Two different images of one name, from two folders, in one daily
note: each gets its own file, and each link shows the bytes of the
image it named.  The same image imported again reuses its file."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--write (expand-file-name "img/a.png" inbox) "FIRST")
    (my/obs-test--write (expand-file-name "shots/a.png" inbox) "SECOND")
    (my/obs-test--write (expand-file-name "2026-10-20.md" inbox)
                        (concat my/obs-test--daily "![](img/a.png) ![](shots/a.png)\n"))
    (let ((target (my/obs-test--journal-file journal)))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (let ((text (my/obs-test--read target)) (links nil) (start 0))
        (while (string-match "\\[\\[file:\\([^]]+\\)\\]\\]" text start)
          (push (match-string 1 text) links)
          (setq start (match-end 0)))
        (should (equal (mapcar (lambda (l) (my/obs-test--read (expand-file-name l)))
                               (nreverse links))
                       '("FIRST" "SECOND"))))
      ;; Imported again into the same journal note: no third file.
      (my/obs-test--write (expand-file-name "2026-10-20.md" inbox)
                          (concat my/obs-test--daily "![](img/a.png)\n"))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (should (= 2 (length (directory-files (expand-file-name "attachments" notes) nil "\\.png\\'"))))
      ;; Another image under the same name, in a later import: a file of
      ;; its own, never the one already there.
      (my/obs-test--write (expand-file-name "img/a.png" inbox) "THIRD")
      (my/obs-test--write (expand-file-name "2026-10-20.md" inbox)
                          (concat my/obs-test--daily "![](img/a.png)\n"))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"))))
      (let ((text (my/obs-test--read target)))
        (should (string-match "\\[\\[file:\\([^]]+\\)\\]\\]\\(?:.\\|\n\\)*\\'" text))
        (let ((last nil) (start 0))
          (while (string-match "\\[\\[file:\\([^]]+\\)\\]\\]" text start)
            (setq last (match-string 1 text) start (match-end 0)))
          (should (equal (my/obs-test--read (expand-file-name last)) "THIRD")))))))

(ert-deftest my/obs-test-script-no-journal-silo-stops ()
  "Without a journal silo the script stops with a failure before it
writes or moves anything."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (delete-directory journal)
    (let ((daily (my/obs-test--daily-file inbox))
          (note (my/obs-test--inbox-note inbox "Szkic.")))
      (let ((result (my/obs-test--script-run vault notes "--settle" "0" "--write")))
        (should-not (= 0 (car result)))
        (should (string-match-p "journal silo not found" (cdr result))))
      (should (file-exists-p daily))
      (should (file-exists-p note))
      (should-not (file-exists-p journal))
      (should-not (file-exists-p (expand-file-name "inbox" notes)))
      (should-not (file-exists-p (expand-file-name "Imported2Emacs" vault))))))

(ert-deftest my/obs-test-script-failure-midway ()
  "When a run fails on a later note, the notes imported before it are
complete -- written, moved, and in the touched list -- and the note it
failed on is not written and stays in the inbox, so that the next run
imports it once."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((setup (my/obs-test--midway-failure vault inbox journal))
           (touched (expand-file-name "touched.txt" root))
           (result (my/obs-test--script-run vault notes "--settle" "0" "--write"
                                            "--touched" touched)))
      (should-not (= 0 (car result)))
      (should (string-search "Rano pisałam o Kancie." (my/obs-test--read (plist-get setup :target))))
      (should-not (file-exists-p (plist-get setup :daily)))
      (should (file-exists-p (expand-file-name "2026-10-20.md" imported)))
      (should (equal (split-string (my/obs-test--read touched) "\n" t)
                     (list (file-truename (plist-get setup :target)))))
      (should (file-exists-p (plist-get setup :late)))
      (should-not (my/obs-test--files (expand-file-name "inbox" notes))))))

(ert-deftest my/obs-test-script-touched-lists-written ()
  "The --touched list names every note written, by its true name: what
Emacs reverts afterwards.  A list left by an earlier run is started
again, not added to."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (my/obs-test--inbox-note inbox "Szkic.")
    (let ((target (my/obs-test--journal-file journal))
          (touched (my/obs-test--write (expand-file-name "touched.txt" root)
                                       "/stale/earlier-run.org\n")))
      (should (= 0 (car (my/obs-test--script-run vault notes "--settle" "0" "--write"
                                                 "--touched" touched))))
      (should (equal (sort (split-string (my/obs-test--read touched) "\n" t) #'string<)
                     (sort (list (file-truename target)
                                 (file-truename
                                  (expand-file-name "inbox/20261020T100000--esej__filozofia.org"
                                                    notes)))
                           #'string<))))))

;; ============================================================
;; THE MODULE: BEFORE A RUN
;; ============================================================

(ert-deftest my/obs-test-check-names-what-is-missing ()
  "The check before a run names what is missing -- the script, Python,
pandoc, the vault -- and says nothing when all is there."
  (my/obs-test--with-tree
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/true")))
      (should-not (my/obsidian-import--check))
      (let ((my/obsidian-import-script (expand-file-name "none.py" root)))
        (should (string-match-p "Import script not found" (my/obsidian-import--check))))
      (let ((my/obsidian-vault-directory (expand-file-name "no-vault/" root)))
        (should (string-match-p "Vault not found" (my/obsidian-import--check)))))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (unless (equal name "python3") "/bin/true"))))
      (should (string-match-p "Python not found" (my/obsidian-import--check))))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (unless (equal name "pandoc") "/bin/true"))))
      (should (string-match-p "pandoc not found" (my/obsidian-import--check))))))

(ert-deftest my/obs-test-run-refuses-before-saving ()
  "A run that cannot start stops with a message before it saves any
buffer or starts any process."
  (my/obs-test--with-tree
    (let* ((file (my/obs-test--journal-file journal))
           (buf (find-file-noselect file))
           (my/obsidian-vault-directory (expand-file-name "no-vault/" root)))
      (with-current-buffer buf (goto-char (point-max)) (insert "unsaved\n"))
      (should-error (my/obsidian-import) :type 'user-error)
      (should (buffer-modified-p buf))
      (should (equal (my/obs-test--read file) my/obs-test--journal-text))
      (should-not (get-buffer-process (get-buffer-create my/obsidian-import-buffer))))))

(ert-deftest my/obs-test-run-refuses-while-running ()
  "While an import runs, a second one is refused before it saves or
starts anything."
  (my/obs-test--with-tree
    (let* ((file (my/obs-test--journal-file journal))
           (buf (find-file-noselect file))
           (busy (make-process :name "obs-test-busy" :command '("sleep" "30")
                               :buffer (get-buffer-create my/obsidian-import-buffer)
                               :noquery t)))
      (unwind-protect
          (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/true")))
            (with-current-buffer buf (goto-char (point-max)) (insert "unsaved\n"))
            (should (equal (my/obsidian-import--check) "An import is already running"))
            (should-error (my/obsidian-import) :type 'user-error)
            (should (buffer-modified-p buf))
            (should (equal (my/obs-test--read file) my/obs-test--journal-text))
            (should (equal (cl-remove-if-not
                            (lambda (p) (eq (process-buffer p) (get-buffer my/obsidian-import-buffer)))
                            (process-list))
                           (list busy))))
        (delete-process busy)))))

(ert-deftest my/obs-test-save-notes-only-under-root ()
  "Before a run the modified buffers of notes are saved; a modified file
outside the notes folder is not -- also one in a folder whose name
merely begins like it, with the notes folder written without a slash."
  (my/obs-test--with-tree
    (let* ((my-notes-dir (directory-file-name notes))
           (note (my/obs-test--journal-file journal))
           (near (my/obs-test--write (expand-file-name "notes-old/x.org" root) "x\n"))
           (away (my/obs-test--write (expand-file-name "elsewhere/y.org" root) "y\n"))
           (bufs (mapcar #'find-file-noselect (list note near away))))
      (dolist (b bufs) (with-current-buffer b (goto-char (point-max)) (insert "typed\n")))
      (should (= 1 (my/obsidian-import--save-notes)))
      (should-not (buffer-modified-p (nth 0 bufs)))
      (should (string-suffix-p "typed\n" (my/obs-test--read note)))
      (should (buffer-modified-p (nth 1 bufs)))
      (should (buffer-modified-p (nth 2 bufs)))
      (should (equal (my/obs-test--read near) "x\n"))
      (should (equal (my/obs-test--read away) "y\n")))))

(ert-deftest my/obs-test-save-notes-through-symlink ()
  "A note buffer is saved whichever name it was opened by: the notes
folder may be a symbolic link, the buffer opened through the folder it
points to, or the other way round."
  (my/obs-test--with-tree
    (let* ((real (file-name-as-directory (expand-file-name "real-notes" root)))
           (link (file-name-as-directory (expand-file-name "linked-notes" root))))
      (make-directory (expand-file-name "journal" real) t)
      (make-symbolic-link (directory-file-name real) (directory-file-name link))
      (let* ((a (my/obs-test--write (expand-file-name "journal/a.org" real) "a\n"))
             (b (my/obs-test--write (expand-file-name "journal/b.org" real) "b\n"))
             ;; One buffer by the folder's own name, one through the link.
             (bufs (list (find-file-noselect a)
                         (find-file-noselect (expand-file-name "journal/b.org" link)))))
        (dolist (my-notes-dir (list link real))
          (dolist (buf bufs)
            (with-current-buffer buf (goto-char (point-max)) (insert "typed\n")))
          (should (= 2 (my/obsidian-import--save-notes)))
          (should-not (cl-some #'buffer-modified-p bufs)))
        (should (equal (my/obs-test--read a) "a\ntyped\ntyped\n"))
        (should (equal (my/obs-test--read b) "b\ntyped\ntyped\n"))))))

;; ============================================================
;; THE MODULE: AFTER A RUN
;; ============================================================

(ert-deftest my/obs-test-revert-leaves-modified-alone ()
  "After a run the buffers of the files written show them as written;
a buffer typed into meanwhile keeps what was typed, and is named."
  (my/obs-test--with-tree
    (let* ((a (my/obs-test--write (expand-file-name "a.org" journal) "a\n"))
           (b (my/obs-test--write (expand-file-name "b.org" journal) "b\n"))
           (buf-a (find-file-noselect a))
           (buf-b (find-file-noselect b)))
      (with-current-buffer buf-b (goto-char (point-max)) (insert "typed meanwhile\n"))
      (my/obs-test--write a "a\nimported\n")
      (my/obs-test--write b "b\nimported\n")
      (should (equal (my/obsidian-import--revert (list a b)) (list (buffer-name buf-b))))
      (should (equal (with-current-buffer buf-a (buffer-string)) "a\nimported\n"))
      (should (equal (with-current-buffer buf-b (buffer-string)) "b\ntyped meanwhile\n"))
      (should (buffer-modified-p buf-b)))))

(ert-deftest my/obs-test-touched-paths-once-each ()
  "A note the touched list names twice -- two daily notes merged into
one journal note -- is reverted and counted once."
  (my/obs-test--with-tree
    (let ((my/obsidian-import--touched-file
           (my/obs-test--write (expand-file-name "touched.txt" root) "/a.org\n/b.org\n/a.org\n")))
      (should (equal (my/obsidian-import--touched-paths) '("/a.org" "/b.org"))))))

(ert-deftest my/obs-test-revert-through-symlink ()
  "A buffer is reverted when the script names its file by the true name
and the buffer was opened through a symbolic link to the notes folder."
  (my/obs-test--with-tree
    (let* ((real (file-name-as-directory (expand-file-name "real-notes" root)))
           (link (file-name-as-directory (expand-file-name "linked-notes" root))))
      (make-directory real t)
      (make-symbolic-link (directory-file-name real) (directory-file-name link))
      (let* ((file (my/obs-test--write (expand-file-name "a.org" real) "a\n"))
             (buf (find-file-noselect (expand-file-name "a.org" link))))
        (my/obs-test--write file "a\nimported\n")
        (should-not (my/obsidian-import--revert (list (file-truename file))))
        (should (equal (with-current-buffer buf (buffer-string)) "a\nimported\n"))))))

;; ============================================================
;; THE MODULE: WHOLE RUNS
;; ============================================================

(ert-deftest my/obs-test-import-saves-then-reverts ()
  "An import into a journal note open with unsaved changes keeps both:
the changes are saved before the script runs, the imported material
is added to the file, and the buffer shows the file as it now is,
unmodified."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (let* ((file (my/obs-test--journal-file journal))
           (buf (find-file-noselect file)))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert "Wieczorem dopisałam to w Emacsie.\n"))
      (should (my/obs-test--run-command #'my/obsidian-import))
      (let ((text (my/obs-test--read file)))
        (should (string-search "Wieczorem dopisałam to w Emacsie." text))
        (should (string-search "Rano pisałam o Kancie." text))
        (with-current-buffer buf
          (should (equal (buffer-string) text))
          (should-not (buffer-modified-p))))
      (should-not my/obsidian-import--touched-file))))

(ert-deftest my/obs-test-dry-run-command-writes-nothing ()
  "The dry-run command runs the script without --write: the journal
note and the vault are unchanged, and the report says it was a dry
run."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let ((daily (my/obs-test--daily-file inbox))
          (file (my/obs-test--journal-file journal)))
      (should (my/obs-test--run-command #'my/obsidian-import-dry-run))
      (should (equal (my/obs-test--read file) my/obs-test--journal-text))
      (should (equal (my/obs-test--read daily) my/obs-test--daily))
      (should-not (file-exists-p (expand-file-name "Imported2Emacs" vault)))
      (should-not my/obsidian-import--touched-file)
      (should (string-match-p "DRY RUN"
                              (with-current-buffer my/obsidian-import-buffer (buffer-string)))))))

(ert-deftest my/obs-test-failed-run-leaves-no-temp-file ()
  "A run the script stops before writing anything reverts nothing,
names the failure in the report, and leaves no temporary list of
touched files behind."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (delete-directory journal)
    (let ((daily (my/obs-test--daily-file inbox))
          (temp nil))
      (should (my/obs-test--run-command
               #'my/obsidian-import
               (lambda () (setq temp my/obsidian-import--touched-file))))
      (should temp)
      (should-not (file-exists-p temp))
      (should-not my/obsidian-import--touched-file)
      (should (file-exists-p daily))
      (should (string-match-p "journal silo not found"
                              (with-current-buffer my/obsidian-import-buffer (buffer-string)))))))

(ert-deftest my/obs-test-failed-run-reverts-what-was-written ()
  "A run that fails midway reverts the notes written before the failure:
an open journal note shows the imported entry, unmodified, and the
temporary list is gone."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let* ((setup (my/obs-test--midway-failure vault inbox journal))
           (buf (find-file-noselect (plist-get setup :target)))
           (temp nil))
      (should (my/obs-test--run-command
               #'my/obsidian-import
               (lambda () (setq temp my/obsidian-import--touched-file))))
      (with-current-buffer buf
        (should (string-search "Rano pisałam o Kancie." (buffer-string)))
        (should-not (buffer-modified-p)))
      (should temp)
      (should-not (file-exists-p temp))
      (should (file-exists-p (plist-get setup :late))))))

(ert-deftest my/obs-test-dry-run-saves-no-buffer ()
  "The dry run writes nothing, buffers included: a note open with unsaved
text stays modified, its file unchanged, and the report says how many
buffers hold changes the dry run does not see."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (my/obs-test--daily-file inbox)
    (let* ((file (my/obs-test--journal-file journal))
           (buf (find-file-noselect file)))
      (with-current-buffer buf (goto-char (point-max)) (insert "unsaved\n"))
      (should (my/obs-test--run-command #'my/obsidian-import-dry-run))
      (should (buffer-modified-p buf))
      (should (equal (my/obs-test--read file) my/obs-test--journal-text))
      (should (string-match-p "1 note buffer(s) hold unsaved changes"
                              (with-current-buffer my/obsidian-import-buffer (buffer-string)))))))

(ert-deftest my/obs-test-inbox-folder-option-reaches-script ()
  "The vault folder named by `my/obsidian-inbox-subdir' is the one the
script reads (until 2026-10-24 the script read its own fixed folder)."
  (skip-unless (my/obs-test--tools-p))
  (my/obs-test--with-tree
    (let ((my/obsidian-inbox-subdir "Telefon"))
      (my/obs-test--write (expand-file-name "Telefon/2026-10-20.md" vault) my/obs-test--daily)
      (my/obs-test--journal-file journal)
      (should (my/obs-test--run-command #'my/obsidian-import-dry-run))
      (should (string-match-p "Telefon/2026-10-20.md | journal-merge"
                              (with-current-buffer my/obsidian-import-buffer (buffer-string)))))))

(provide 'test-obsidian-import)
;;; test-obsidian-import.el ends here
