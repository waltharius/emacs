;;; 417d-zotero-annotations.el --- Zotero's annotations of a PDF or EPUB into a note -*- lexical-binding: t; -*-

;; MyPKS-Requires: 417-bibliography 417c-zotero
;; MyPKS-Optional: yes
;; MyPKS-Default: off
;; Docs: ~/.emacs.d/function_helper.org::#zotero-annotations

;;; Commentary:

;; Reads the highlights, underlines and notes made in Zotero's reader on
;; a reference's PDF or EPUB and inserts them into the Org note at point,
;; each as a quote with a link that opens the annotation in Zotero
;; (C-c x a).  Read only: nothing is written to Zotero.
;;
;; The source is Zotero's local API (Zotero 10 or newer; Settings ->
;; Advanced -> "Allow other applications on this computer to communicate
;; with Zotero"), on localhost, with no account and no key.  Not the
;; Web API: that one needs a key and the network, and it serves what was
;; last synced, not what is in the reader now.  Not zotero.sqlite
;; directly: Zotero 10 keeps it in WAL mode and its developers advise
;; against reading it from outside.
;;
;; Which file: the reference's files as citar finds them; a file inside
;; Zotero's attachments folder (`my/zotero-storage-directory',
;; 417c-zotero.el) sits in a folder named after the key of its attachment
;; item, ~/Zotero/storage/<KEY>/file.pdf.  That key is what an
;; annotation's parentItem names.
;;
;; Which annotations: every annotation item of the library, filtered by
;; parentItem.  GET .../items/<attachment>/children, the obvious request,
;; answers with an empty list on Zotero 10.0.2 for an attachment with
;; 103 annotations (checked 2026-11-03), while ?itemType=annotation
;; returns them all.  The list is read once per command, on localhost.
;;
;; Which of them: the command lists the annotations not yet in the note,
;; in reading order, one line each (page, text, comment), to search and
;; choose one or several with `completing-read-multiple', the prompt
;; used for several choices elsewhere here (separator `crm-separator',
;; a comma, 101-ui.el).  The first line inserts all of them, and is the
;; one RET takes before anything is typed.  Chosen annotations go in in
;; reading order, whatever the order they were chosen in.
;;
;; Not yet in the note: every inserted annotation carries its key in the
;; link (annotation=KEY), and annotations whose key is already in the
;; buffer are not offered.  Deleting an annotation in Zotero leaves its
;; quote in the note; the note is the user's text.
;;
;; Page numbers: a PDF annotation carries its page label, the number
;; printed on the page when the PDF says so, otherwise the page's
;; position in the file.  An EPUB annotation carries one only when the
;; EPUB maps its text to printed pages; without it the link names no
;; page.

;;; Code:

(require 'crm)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-http)

(defvar my/zotero-storage-directory)
(declare-function citar-get-files "citar" (&optional citekey-or-citekeys))
(declare-function citar-select-ref "citar" (&rest args))
(declare-function citar-denote--retrieve-references "citar-denote" (file))
(declare-function org-link-set-parameters "ol" (type &rest parameters))

;; ============================================================
;; SETTINGS
;; ============================================================

(defcustom my/zotero-api-url "http://localhost:23119/api/"
  "Address of Zotero's local API, ending in a slash.
Zotero serves it on this computer only, while it runs, once Settings ->
Advanced -> \"Allow other applications on this computer to communicate
with Zotero\" is on."
  :type 'string
  :tag "Zotero local API address"
  :group 'my/bibliography)

(defcustom my/zotero-annotations-page-format "p. %s"
  "How the link of an inserted annotation names its page.
A format string with one %s, the page label from Zotero: \"p. %s\"
gives \"p. 40\", \"s. %s\" gives \"s. 40\"."
  :type 'string
  :tag "Zotero annotations: page label"
  :group 'my/bibliography)

(defcustom my/zotero-annotations-skip-colors nil
  "Colours of Zotero annotations that are not inserted.
Hex strings as Zotero writes them, such as \"#aaaaaa\" for grey: for
highlights used to mark headings or for navigation rather than as
quotes.  Empty: every colour."
  :type '(repeat (string :tag "Colour, #rrggbb"))
  :tag "Zotero annotations: colours left out"
  :group 'my/bibliography)

(defcustom my/zotero-annotations-join-hyphens t
  "Non-nil: join words the PDF broke at the end of a line.
Text selected across a line break comes from Zotero as \"indywidual-
nego\"; joined, it reads \"indywidualnego\".  A hyphen followed by a
space and a lower-case letter is taken for such a break, so a
suspended hyphen (\"biało- i czerwony\") is joined too."
  :type 'boolean
  :tag "Zotero annotations: join words broken at line ends"
  :group 'my/bibliography)

;; ============================================================
;; LOCAL API
;; ============================================================

(defun my/zotero-annotations--get (path)
  "GET PATH of Zotero's local API; return the parsed JSON.
Objects become alists with symbol keys, arrays lists.  Signals a
`user-error' that says what to check when Zotero does not answer or
refuses, rather than returning nothing, so a refusal cannot read as a
reference without annotations."
  (let* ((url (concat my/zotero-api-url path))
         (url-request-method "GET")
         (buffer (condition-case nil
                     (url-retrieve-synchronously url t t 30)
                   (error nil))))
    (unless buffer
      (user-error "Zotero: no answer at %s -- is Zotero running?" my/zotero-api-url))
    (with-current-buffer buffer
      (unwind-protect
          (progn
            (goto-char (point-min))
            (unless (looking-at "HTTP/[0-9.]+ \\([0-9]+\\)")
              (user-error "Zotero: malformed reply from %s" url))
            (let ((status (string-to-number (match-string 1))))
              (cond
               ((= status 403)
                (user-error "Zotero refused the request: turn on Settings -> Advanced -> %s"
                            "'Allow other applications on this computer to communicate with Zotero'"))
               ((/= status 200)
                (user-error "Zotero: HTTP %d for %s" status path))))
            (unless (re-search-forward "\r?\n\r?\n" nil t)
              (user-error "Zotero: malformed reply from %s" url))
            ;; The reply buffer is unibyte and holds the bytes as sent;
            ;; Zotero sends UTF-8.
            (json-parse-string
             (decode-coding-string
              (buffer-substring-no-properties (point) (point-max)) 'utf-8)
             :object-type 'alist :array-type 'list
             :null-object nil :false-object nil))
        (kill-buffer buffer)))))

(defun my/zotero-annotations--of (attachment items)
  "Return the annotations among ITEMS whose parent is ATTACHMENT.
ITEMS as the local API lists them.  Sorted as Zotero's reader shows
them (`annotationSortIndex': page, then position on the page), colours
in `my/zotero-annotations-skip-colors' left out."
  (let ((skip (mapcar #'downcase my/zotero-annotations-skip-colors)))
    (sort (seq-filter
           (lambda (item)
             (let ((data (alist-get 'data item)))
               (and (equal (alist-get 'itemType data) "annotation")
                    (equal (alist-get 'parentItem data) attachment)
                    (not (member (downcase (or (alist-get 'annotationColor data) ""))
                                 skip)))))
           items)
          (lambda (a b)
            (string< (or (alist-get 'annotationSortIndex (alist-get 'data a)) "")
                     (or (alist-get 'annotationSortIndex (alist-get 'data b)) ""))))))

;; ============================================================
;; FILES AND KEYS
;; ============================================================

(defun my/zotero-annotations--attachment-key (file)
  "Return the key of the Zotero attachment FILE is, or nil.
A file directly in a folder of `my/zotero-storage-directory' whose name
is a Zotero key (eight capitals or digits) is that attachment's file."
  (when my/zotero-storage-directory
    (let ((storage (file-name-as-directory
                    (file-truename (expand-file-name my/zotero-storage-directory))))
          (dir (file-name-directory (file-truename (expand-file-name file))))
          ;; Keys are capitals: "j27dmsmh" is not one.
          (case-fold-search nil))
      (when (and (string-prefix-p storage dir)
                 (string-match "\\`\\([A-Z0-9]\\{8\\}\\)/\\'"
                               (substring dir (length storage))))
        (match-string 1 (substring dir (length storage)))))))

(defun my/zotero-annotations--attachments (citekey)
  "Return (FILE . KEY) for each PDF or EPUB of CITEKEY in Zotero's folder.
The files are the ones citar finds for CITEKEY."
  (require 'citar)
  (let* ((table (citar-get-files citekey))
         (files (and (hash-table-p table) (gethash citekey table))))
    (delq nil
          (mapcar (lambda (file)
                    (when-let* (((string-match-p "\\.\\(pdf\\|epub\\)\\'" (downcase file)))
                                (key (my/zotero-annotations--attachment-key file)))
                      (cons file key)))
                  files))))

(defun my/zotero-annotations--citekey ()
  "Return the citation key of the note in this buffer, or ask for one.
The key is the note's #+reference, as citar-denote writes it; without
one the reference is chosen with citar."
  (or (and buffer-file-name
           (fboundp 'citar-denote--retrieve-references)
           (car (citar-denote--retrieve-references buffer-file-name)))
      (progn (require 'citar)
             (citar-select-ref))))

;; ============================================================
;; ORG TEXT
;; ============================================================

(defun my/zotero-annotations--clean (text)
  "Return TEXT on one line, words broken at line ends joined.
Joining follows `my/zotero-annotations-join-hyphens'.  A leading `*' or
`#' gets a space before it, so the line cannot become an Org heading or
keyword."
  (let ((one (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " (or text ""))))
        ;; [:lower:] is lower case only without case folding.
        (case-fold-search nil))
    (when my/zotero-annotations-join-hyphens
      (setq one (replace-regexp-in-string "\\([[:alpha:]]\\)- \\([[:lower:]]\\)"
                                          "\\1\\2" one)))
    (if (string-match-p "\\`[*#]" one) (concat " " one) one)))

(defun my/zotero-annotations--org (item attachment)
  "Return the Org text of the annotation ITEM of ATTACHMENT.
A quote of its text, when it has one; a link that opens it in Zotero,
named after its page; its comment."
  (let* ((data (alist-get 'data item))
         (key (alist-get 'key data))
         (type (alist-get 'annotationType data))
         (text (my/zotero-annotations--clean (alist-get 'annotationText data)))
         (comment (string-trim (or (alist-get 'annotationComment data) "")))
         (page (alist-get 'annotationPageLabel data))
         (label (concat (if (and page (not (string-empty-p page)))
                            (format my/zotero-annotations-page-format page)
                          "Zotero")
                        ;; Image and ink annotations have no text: say what
                        ;; the link opens.
                        (if (member type '("image" "ink")) (concat ", " type) ""))))
    (concat (unless (string-empty-p text)
              (concat "#+begin_quote\n" text "\n#+end_quote\n"))
            (format "[[zotero://open-pdf/library/items/%s?annotation=%s][%s]]\n"
                    attachment key label)
            (unless (string-empty-p comment)
              (concat "\n" comment "\n"))
            "\n")))

(defun my/zotero-annotations--present ()
  "Return the keys of the Zotero annotations already linked in the buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search nil)
          keys)
      (while (re-search-forward "zotero://open-pdf/[^]\n]*annotation=\\([A-Z0-9]+\\)" nil t)
        (push (match-string-no-properties 1) keys))
      keys)))

;; ============================================================
;; CHOOSING
;; ============================================================

(defconst my/zotero-annotations--all-label "* All new annotations"
  "Beginning of the first line of the list, which inserts every annotation.")

(defun my/zotero-annotations--label (item)
  "Return the line of the annotation ITEM in the list to choose from.
Page, text and comment on one line.  What `crm-separator' matches
becomes a space: in a label it would split the choice in two."
  (let* ((data (alist-get 'data item))
         (page (alist-get 'annotationPageLabel data))
         (text (string-trim (my/zotero-annotations--clean (alist-get 'annotationText data))))
         (comment (string-trim (replace-regexp-in-string
                                "[ \t\n\r]+" " "
                                (or (alist-get 'annotationComment data) "")))))
    (string-trim
     (replace-regexp-in-string
      crm-separator " "
      (string-join
       (delq nil (list (if (and page (not (string-empty-p page)))
                           (format my/zotero-annotations-page-format page)
                         "-")
                       (if (string-empty-p text)
                           (format "[%s]" (alist-get 'annotationType data))
                         text)
                       (unless (string-empty-p comment) (concat "» " comment))))
       "  ")))))

(defun my/zotero-annotations--candidates (items)
  "Return (LABEL . ITEM) for each of ITEMS, labels made unique.
Two annotations with the same line get a number after it: (2), (3)..."
  (let ((seen (make-hash-table :test #'equal))
        pairs)
    (dolist (item items (nreverse pairs))
      (let* ((label (my/zotero-annotations--label item))
             (count (1+ (gethash label seen 0))))
        (puthash label count seen)
        (push (cons (if (= count 1) label (format "%s (%d)" label count)) item)
              pairs)))))

(defun my/zotero-annotations--choose (items)
  "Let the user choose among ITEMS; return the chosen ones in reading order.
ITEMS are in reading order.  The first line of the list, chosen alone
or with others, returns all of them; so does RET before anything is
typed."
  (let* ((pairs (my/zotero-annotations--candidates items))
         (all (format "%s (%d)" my/zotero-annotations--all-label (length items)))
         (lines (cons all (mapcar #'car pairs)))
         ;; Kept in reading order: without the metadata the completion
         ;; frontend sorts the lines by its own rules.
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action lines string pred))))
         (picked (completing-read-multiple
                  "Zotero annotations (search; several with a comma; RET on the first: all): "
                  table nil t nil nil all)))
    (if (or (null picked) (member all picked))
        items
      (let ((chosen (delq nil (mapcar (lambda (label) (cdr (assoc label pairs))) picked))))
        (seq-filter (lambda (item) (memq item chosen)) items)))))

;; ============================================================
;; COMMAND
;; ============================================================

(defun my/zotero-annotations-insert ()
  "Insert at point Zotero annotations of this note's PDF or EPUB.
The reference is the note's #+reference, or one chosen with citar; with
several PDF or EPUB files in Zotero, the file is asked for.  The
annotations not yet linked in the buffer are listed to search and
choose from (`my/zotero-annotations--choose'); the first line, which
RET takes at once, inserts all of them."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Zotero annotations go into an Org note"))
  (let* ((citekey (or (my/zotero-annotations--citekey)
                      (user-error "No reference chosen")))
         (attachments (my/zotero-annotations--attachments citekey))
         (attachment
          (cond
           ((null attachments)
            (user-error "No PDF or EPUB of %s in Zotero's attachments folder (%s)"
                        citekey my/zotero-storage-directory))
           ((null (cdr attachments)) (cdar attachments))
           (t (cdr (assoc (completing-read "File: " (mapcar #'car attachments) nil t)
                          attachments)))))
         (all (my/zotero-annotations--of
               attachment (my/zotero-annotations--get "users/0/items?itemType=annotation")))
         (present (my/zotero-annotations--present))
         (new (seq-remove (lambda (item)
                            (member (alist-get 'key (alist-get 'data item)) present))
                          all)))
    (if (null new)
        (message "Zotero: no new annotations for %s (%d already in the note)"
                 citekey (length all))
      (let ((chosen (my/zotero-annotations--choose new)))
        (insert (mapconcat (lambda (item) (my/zotero-annotations--org item attachment))
                           chosen ""))
        (message "Zotero: %d of %d new annotation(s) of %s inserted%s"
                 (length chosen) (length new) citekey
                 (if (= (length new) (length all)) ""
                   (format ", %d already in the note" (- (length all) (length new)))))))))

;; ============================================================
;; LINKS
;; ============================================================
;; zotero: links open in Zotero itself: the desktop app registers the
;; zotero:// scheme with the system, and `browse-url' hands it there.

(defun my/zotero-annotations--follow (path _arg)
  "Open the zotero: link PATH in Zotero."
  (browse-url (concat "zotero:" path)))

(with-eval-after-load 'ol
  (org-link-set-parameters "zotero" :follow #'my/zotero-annotations--follow))

;; ============================================================
;; MENU
;; ============================================================

(with-eval-after-load '212-transient
  (when (fboundp 'my/transient-entries)
    (my/transient-entries
     t '((append my/bibliography-menu "o"
                 ("a" "Zotero annotations: choose or all" my/zotero-annotations-insert))))))

(provide '417d-zotero-annotations)
;;; 417d-zotero-annotations.el ends here
