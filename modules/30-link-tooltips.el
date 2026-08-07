;;; 30-link-tooltips.el --- Cheap mouse tooltips over denote: links -*- lexical-binding: t; -*-

;;; Commentary:
;; Hovering the mouse over a `denote:' link in an Org buffer stalls
;; Emacs for as long as it takes to list the entire `denote-directory'.
;;
;; WHY
;;
;; Denote registers a `:help-echo' FUNCTION for its Org link type:
;;
;;   (org-link-set-parameters "denote"
;;     :follow #'denote-link-ol-follow
;;     :help-echo #'denote-link-ol-help-echo
;;     ...)
;;
;; Org stores whatever `:help-echo' holds in the `help-echo' text
;; property.  A string is computed once, during fontification; a
;; function is called by redisplay every time the mouse pointer lands on
;; the link, and again as the pointer moves across it.
;;
;; `denote-link-ol-help-echo' resolves the identifier with
;; `denote-get-path-by-id', which calls `denote-directory-files', which
;; walks the whole notes tree with `directory-files-recursively'.
;; Nothing in Denote caches that result.  With a few thousand notes this
;; is a full recursive stat of the tree per pointer movement, which is
;; exactly the observed freeze.  It is invisible on a small collection
;; and becomes unusable somewhere in the low thousands of files.
;;
;; WHAT IS TRADED
;;
;; The tooltip is informational only: it names the file behind a link
;; whose title is already printed on screen.  Paying a directory scan
;; for that is a bad trade, so this module replaces the function.
;;
;; Only the tooltip changes.  Following a link still goes through
;; Denote's `:follow', which resolves the identifier freshly, so a note
;; moved between devices by Syncthing is always opened from its current
;; location.  A stale tooltip can at worst name a path that has since
;; changed, and nothing acts on that text.
;;
;; STYLES -- `my/link-tooltip-style'
;;
;;   `identifier'  show the raw denote: target.  No file system access
;;                 at all.  Default.
;;   `path'        show the resolved path, memoised for
;;                 `my/link-tooltip-cache-seconds'.  One scan per burst
;;                 of hovering instead of one per pointer movement.
;;   `default'     hand the parameter back to Org, which then builds its
;;                 own "LINK: ..." string at fontification time.
;;
;; DEPENDENCIES
;;
;; Org and Denote, both checked before anything is installed; if either
;; is absent the module reports and does nothing.  `12-transient.el' is
;; optional: the View-menu entry goes through `my/transient-append',
;; which skips silently when the menu or the helper is missing.
;;
;; RELATED
;;
;; The scanning section of `04-denote.el' explains why nothing caches
;; `denote-directory-files' globally.  The cache below is deliberately
;; local to tooltips and short-lived, so no Denote prompt, backlink
;; buffer or search can ever be served from it.
;;
;; Docs: ~/.emacs.d/function_helper.org::#link-tooltips

;;; Code:

(require 'subr-x)

;; ============================================================
;; CONFIG
;; ============================================================

(defgroup my/link-tooltips nil
  "Mouse tooltips over Denote links."
  :group 'my)

(defcustom my/link-tooltip-style 'identifier
  "What the tooltip over a `denote:' Org link shows.

`identifier' names the link target and touches no files.
`path' resolves the target to a file name, memoised for
`my/link-tooltip-cache-seconds'.
`default' removes the parameter so Org supplies its own text.

Changing this takes effect immediately for `identifier' and
`path'.  Switching to or from `default' changes a text property
that Org writes during fontification, so affected buffers need
`font-lock-flush'; `my/link-tooltip-set-style' does that for the
current buffer."
  :type '(choice (const :tag "Link target only (no disk access)" identifier)
                 (const :tag "Resolved file path (cached)" path)
                 (const :tag "Org's own text" default))
  :group 'my/link-tooltips)

(defcustom my/link-tooltip-cache-seconds 30
  "How long a resolved path may be reused, in seconds.

Only consulted when `my/link-tooltip-style' is `path'.  The whole
cache is dropped once this many seconds have passed since it was
filled, so the upper bound on how wrong a tooltip can be is this
value.  Lower it towards zero to approach Denote's own behaviour,
including its cost."
  :type 'number
  :group 'my/link-tooltips)

;; ============================================================
;; CACHE
;; ============================================================
;; Declared before any `setq' that references them: init aborts on a
;; `setq' to an undeclared symbol under lexical binding in some load
;; orders, and these are written from a timer-free code path that must
;; not fail inside redisplay.

(defvar my/link-tooltip--cache (make-hash-table :test #'equal)
  "Identifier to file path, or nil for identifiers that resolve to nothing.")

(defvar my/link-tooltip--cache-filled 0
  "`float-time' at which `my/link-tooltip--cache' was last emptied.")

(defun my/link-tooltip-clear-cache ()
  "Empty the tooltip path cache.

Needed only after moving or deleting notes while a tooltip is
still expected to show the old location; the cache expires on its
own after `my/link-tooltip-cache-seconds'."
  (interactive)
  (clrhash my/link-tooltip--cache)
  (setq my/link-tooltip--cache-filled (float-time))
  (when (called-interactively-p 'interactive)
    (message "Link tooltip cache cleared")))

(defun my/link-tooltip--resolve (id)
  "Return the file path for Denote identifier ID, or nil.

Result is memoised for `my/link-tooltip-cache-seconds'.  Failures
are cached too: an identifier with no file behind it is a broken
link, and retrying the full directory scan on every pointer
movement is the cost this module exists to avoid."
  (when (fboundp 'denote-get-path-by-id)
    (when (> (- (float-time) my/link-tooltip--cache-filled)
             my/link-tooltip-cache-seconds)
      (clrhash my/link-tooltip--cache)
      (setq my/link-tooltip--cache-filled (float-time)))
    (let ((hit (gethash id my/link-tooltip--cache 'my/link-tooltip--miss)))
      (if (eq hit 'my/link-tooltip--miss)
          (puthash id (ignore-errors (denote-get-path-by-id id))
                   my/link-tooltip--cache)
        hit))))

;; ============================================================
;; READING THE LINK UNDER THE POINTER
;; ============================================================

(defconst my/link-tooltip--denote-target-regexp
  "denote:\\([^]\n\t \"'<>]+\\)"
  "Match a `denote:' link target, capturing the identifier and any suffix.")

(defun my/link-tooltip--target-from-property (object position)
  "Return the `denote:' target at POSITION in OBJECT, from text properties.

Org's `org-activate-links' stores the raw link under `htmlize-link',
which is also where Denote's own tooltip function reads it from.
OBJECT is a buffer or a propertised string, as passed to a
`help-echo' function."
  (let ((uri (if (bufferp object)
                 (with-current-buffer object
                   (get-text-property position 'htmlize-link))
               (get-text-property position 'htmlize-link object))))
    (when-let* ((raw (plist-get uri :uri))
                ((string-prefix-p "denote:" raw)))
      (substring raw (length "denote:")))))

(defun my/link-tooltip--target-from-line (object position)
  "Return the `denote:' target at POSITION in OBJECT by scanning its line.

Fallback for the case where `htmlize-link' is absent, which
happens with link types fontified by something other than
`org-activate-links'.  The search is bounded to the surrounding
line, so its cost does not grow with buffer size."
  (when (bufferp object)
    (with-current-buffer object
      (save-excursion
        (save-restriction
          (widen)
          (goto-char position)
          (let ((bol (line-beginning-position))
                (eol (line-end-position))
                (found nil))
            (goto-char bol)
            (while (and (not found)
                        (re-search-forward my/link-tooltip--denote-target-regexp
                                           eol t))
              (when (and (<= (match-beginning 0) position)
                         (>= (match-end 0) position))
                (setq found (match-string-no-properties 1))))
            found))))))

(defun my/link-tooltip--target (object position)
  "Return the `denote:' target at POSITION in OBJECT, or nil."
  (or (my/link-tooltip--target-from-property object position)
      (my/link-tooltip--target-from-line object position)))

;; ============================================================
;; THE REPLACEMENT HELP-ECHO
;; ============================================================

(defun my/denote-link-help-echo (_window object position)
  "Tooltip text for the `denote:' link at POSITION in OBJECT.

Signature required by Org's `:help-echo' link parameter.  Returns
nil when the target cannot be read, which suppresses the tooltip
rather than showing something misleading."
  (when-let* ((target (my/link-tooltip--target object position)))
    (pcase my/link-tooltip-style
      ('path
       ;; A target may carry a heading suffix: "ID#heading" in current
       ;; Denote, "ID::heading" in Org's own syntax.  Only the leading
       ;; identifier is looked up.
       (let ((id (if (string-match "\\`\\([^#:]+\\)" target)
                     (match-string 1 target)
                   target)))
         (or (my/link-tooltip--resolve id)
             (format "denote:%s (no file with this identifier)" target))))
      (_ (concat "denote:" target)))))

;; ============================================================
;; INSTALLATION
;; ============================================================

(defun my/link-tooltips--parameter ()
  "Value to give Org's `:help-echo' for the `denote:' link type."
  (unless (eq my/link-tooltip-style 'default)
    #'my/denote-link-help-echo))

(defun my/link-tooltips-apply ()
  "Install the current `my/link-tooltip-style' on the `denote:' link type.

Does nothing, with a message, unless both Org's link API and
Denote's identifier lookup are available."
  (cond
   ((not (fboundp 'org-link-set-parameters))
    (message "30-link-tooltips: Org link API missing; denote: tooltips left alone"))
   ((not (fboundp 'denote-get-path-by-id))
    (message "30-link-tooltips: Denote missing; denote: tooltips left alone"))
   (t
    (org-link-set-parameters "denote" :help-echo (my/link-tooltips--parameter))
    t)))

(defun my/link-tooltip-set-style (style)
  "Set `my/link-tooltip-style' to STYLE and apply it.

Refontifies the current buffer, because Org decides between its
own tooltip text and this module's function while fontifying."
  (interactive
   (list (intern (completing-read
                  "Denote link tooltip: "
                  '("identifier" "path" "default")
                  nil t nil nil
                  (symbol-name my/link-tooltip-style)))))
  (setq my/link-tooltip-style style)
  (my/link-tooltip-clear-cache)
  (my/link-tooltips-apply)
  (when (derived-mode-p 'org-mode)
    (font-lock-flush))
  (message "Denote link tooltip: %s" style))

;; Denote registers its Org link parameters inside its own
;; `with-eval-after-load' on org, evaluated when Denote loads.  Nesting
;; the two forms this way guarantees this runs after that registration
;; whichever package loads first.
(with-eval-after-load 'denote
  (with-eval-after-load 'org
    (my/link-tooltips-apply)))

;; ============================================================
;; MENU
;; ============================================================
;; Appended to the View submenu after "e" (Emphasis markers).  Skipped
;; without complaint when 12-transient.el is not loaded.

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-view-menu "e"
                       '("T" "Link tooltips" my/link-tooltip-set-style)))

(provide '30-link-tooltips)
;;; 30-link-tooltips.el ends here
