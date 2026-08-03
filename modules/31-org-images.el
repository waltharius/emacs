;;; 31-org-images.el --- Image attachments for notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Pick an image from disk, shrink it, park it in ~/notes/attachments/
;; under the identifier of the note it is inserted into, and link it at
;; point.  Clicking the inline preview opens the file at full size.
;;
;; Entry points:
;;
;;   `my/org-image-insert'                  C-c n i i
;;   `my/org-image-attachments-dired'       C-c n i I
;;   `my/org-image-recompress-attachments'  M-x, one-off cleanup
;;   mouse-1 / RET on a preview             open the image
;;   x on a preview                         open it in the desktop viewer
;;
;; HOW ATTACHMENTS ARE NAMED
;;
;;   IDENTIFIER--TITLE-SLUG-N.EXT
;;   20241225T000000--25-12-2024-środa-0.png
;;
;; The identifier is the NOTE's, taken from its file name; the slug comes
;; from its `#+title:'; N counts from 0 within that note.  So every
;; attachment of one note sorts next to its siblings, a file whose
;; identifier matches no note is an orphan by inspection, and the folder
;; stays readable after a thousand files -- which IMG_2451.jpg does not.
;;
;; Reusing the note's identifier means two files under ~/notes/ carry the
;; same one, which is what 27-denote-identifiers.el exists to report.  It
;; reads .org files only, so images never reach it; the exposure is
;; Denote itself, which walks the whole tree for every prompt.  This
;; module therefore adds the folder to
;; `denote-excluded-directories-regexp' -- extending, never replacing,
;; the value 25-inbox-review.el sets for the staging inbox.
;;
;; WHY RESIZING ALONE IS NOT ENOUGH
;;
;; PNG is lossless.  Rescaling a 4 MB screenshot to 1600 px and writing
;; it back as PNG gives roughly 4 MB again: fewer pixels, each one still
;; stored exactly.  Measured on a 2559x1639 terminal screenshot:
;;
;;   resize to 1600 px, PNG          551 kB -> 489 kB
;;   the same, then -colors 256      551 kB -> 133 kB
;;   the same, then JPEG q85         551 kB -> 146 kB
;;
;; Size only falls once fidelity is traded, so the pipeline is a ladder
;; and each rung runs only if the one before left the file over
;; `my/org-image-max-bytes':
;;
;;   1. rescale to `my/org-image-max-pixels' (never enlarge)
;;   2. under budget?  stop -- the file is still pixel-exact
;;   3. few colours in the source (screenshot, diagram, chart)?
;;      quantise to a 256-colour palette, keeping PNG and its alpha
;;   4. otherwise, or if step 3 was not enough: JPEG, with
;;      `jpeg:extent' as a ceiling
;;
;; Step 3 before step 4 on purpose: quantising keeps text edges crisp,
;; while JPEG puts ringing around every letter.  The two are told apart
;; by counting distinct colours in a nearest-neighbour sample of the
;; SOURCE (`-sample', not `-resize': interpolation invents colours and
;; would make every screenshot look photographic).  A screenshot lands
;; around a thousand, a photograph in the hundred thousands.
;;
;; All of this needs ImageMagick (`magick', or `convert' on version 6) on
;; PATH; on NixOS, `imagemagick' in the system packages.  Without it, or
;; for a format it has no delegate for, the file is copied unchanged and
;; the echo area says so.  Nothing fails.
;;
;; WHY CLICKING OPENS THE FILE INSTEAD OF GROWING THE PREVIEW
;;
;; Org's preview is one scaled bitmap in an overlay.  Growing it in place
;; rescales that bitmap inside a text buffer, reflows everything below
;; it, and loses the size at the next image refresh.  Opening the file
;; gives full resolution with panning and zooming that already work.
;; `image-map' stays the parent keymap, so `i +' still does what it did.
;;
;; DEPENDENCIES
;;
;; Org is required.  Denote is optional and only supplies the identifier.
;; ImageMagick is optional, as described above.  12-transient.el is
;; optional: the menu entries go through `my/transient-append', which
;; reports and skips when the menu or the helper is absent.
;;
;; RELATED
;;
;; 11-org-appearance.el  display width of inline images
;; 25-inbox-review.el    owns the base `denote-excluded-directories-regexp'
;; 26-maintenance.el     integrity checks; reads .org files only
;;
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-org-image-insert

;;; Code:

(require 'org)
(require 'image)
(require 'seq)
(require 'subr-x)

;; ============================================================
;; CONFIG
;; ============================================================

(defcustom my/org-image-attachments-directory
  (expand-file-name "attachments/"
                    (if (boundp 'my-notes-dir) my-notes-dir "~/notes/"))
  "Directory holding images referenced from notes.
Kept inside the notes tree so that Syncthing carries attachments and
notes together, and excluded from Denote's file listing at load time."
  :type 'directory
  :group 'my)

(defcustom my/org-image-max-pixels 1600
  "Longer edge of a stored attachment, in pixels.
Images are never enlarged: a source smaller than this keeps its size.
Nil stores every image at its original resolution."
  :type '(choice (const :tag "Do not resize" nil) integer)
  :group 'my)

(defcustom my/org-image-max-bytes (* 300 1024)
  "Size an attachment should not exceed once stored.
A file still over this after rescaling is quantised or re-encoded as
JPEG; see the ladder in the commentary.  Nil rescales only, which for a
PNG source means almost no saving at all."
  :type '(choice (const :tag "No budget" nil) integer)
  :group 'my)

(defcustom my/org-image-palette-max-colors 4096
  "Colour count below which an image is treated as a screenshot.
Counted in a 400x400 nearest-neighbour sample of the source.  Below the
threshold the file is quantised to 256 colours and stays PNG; above it,
JPEG is used instead.  Lower this if screenshots come out looking like
JPEG; raise it if photographs come out banded."
  :type 'integer
  :group 'my)

(defcustom my/org-image-jpeg-quality 85
  "JPEG quality used when an image has to be re-encoded, 1-100."
  :type 'integer
  :group 'my)

(defcustom my/org-image-no-resize-extensions '("svg" "svgz" "gif")
  "Extensions copied verbatim, without going through the converter.
SVG is a vector format, so pixel dimensions mean nothing; an animated
GIF would have to be coalesced frame by frame and usually grows."
  :type '(repeat string)
  :group 'my)

(defcustom my/org-image-source-directory nil
  "Directory the file prompt starts in.
Nil picks the first of ~/Pictures/, ~/Obrazy/, ~/Downloads/, ~/Pobrane/
that exists, and falls back to the home directory."
  :type '(choice (const :tag "Guess" nil) directory)
  :group 'my)

(defcustom my/org-image-prompt-for-name t
  "Whether to ask for the attachment name.
The note's title is offered as the default, so RET accepts it.  Nil
skips the prompt and uses the title without asking."
  :type 'boolean
  :group 'my)

(defcustom my/org-image-link-style 'relative
  "Whether inserted links are relative to the note or absolute.
Relative links survive a home directory that differs between machines,
which absolute ones do not; both resolve the same on one machine."
  :type '(choice (const relative) (const absolute))
  :group 'my)

(defcustom my/org-image-attr-width nil
  "Width written as `#+ATTR_ORG: :width' above each inserted link.
Nil inserts no attribute, leaving the size to `org-image-actual-width'
in 11-org-appearance.el -- the right default, since a per-image
attribute overrides the global setting for good and has to be edited by
hand afterwards."
  :type '(choice (const :tag "Use the global width" nil) integer string)
  :group 'my)

(defcustom my/org-image-click-action 'emacs
  "What mouse-1 on an inline image preview does.
`emacs' opens the file in an Emacs `image-mode' buffer, `external'
hands it to the desktop image viewer, and nil leaves Org's own overlay
keymap alone."
  :type '(choice (const :tag "Emacs image buffer" emacs)
                 (const :tag "Desktop viewer" external)
                 (const :tag "Nothing" nil))
  :group 'my)

(defvar my/org-image-extensions
  '("png" "jpg" "jpeg" "gif" "webp" "avif" "heic" "tif" "tiff"
    "bmp" "svg" "svgz" "pnm" "ppm" "pgm" "xpm" "ico")
  "Extensions offered by the file prompt.")

;; ============================================================
;; DENOTE: keep the attachment folder out of the note listing
;; ============================================================
;; The base value belongs to 25-inbox-review.el and is extended here,
;; never overwritten; evaluating this twice is harmless.

(with-eval-after-load 'denote
  (let ((name (file-name-nondirectory
               (directory-file-name my/org-image-attachments-directory))))
    (when (and (stringp name) (not (string-empty-p name)))
      (let ((current (and (boundp 'denote-excluded-directories-regexp)
                          denote-excluded-directories-regexp)))
        (unless (and current (string-match-p (regexp-quote name) current))
          (setq denote-excluded-directories-regexp
                (if current
                    (concat current "\\|" (regexp-quote name))
                  (regexp-quote name))))))))

;; ============================================================
;; NAMING
;; ============================================================

(defun my/org-image--slug (string)
  "Return STRING as a file name fragment.
Non-ASCII letters are kept as they are: file names in this
configuration carry Polish characters unchanged."
  (let* ((s (downcase (or string "")))
         (s (replace-regexp-in-string "[^[:alnum:]]+" "-" s))
         (s (replace-regexp-in-string "-\\{2,\\}" "-" s))
         (s (string-trim s "-+" "-+")))
    (if (string-empty-p s)
        "image"
      (substring s 0 (min (length s) 60)))))

(defun my/org-image--note-title ()
  "Return the `#+title:' of the current buffer, or nil."
  (or (and (fboundp 'org-collect-keywords)
           (cadr (assoc "TITLE" (org-collect-keywords '("TITLE")))))
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+title:[ \t]+\\(.*[^ \t\n]\\)"
                                 (min 4096 (point-max)) t)
          (match-string-no-properties 1)))))

(defun my/org-image--identifier-from-front-matter ()
  "Return the `#+identifier:' of the current buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+identifier:[ \t]+\\([^ \t\n]+\\)"
                             (min 4096 (point-max)) t)
      (match-string-no-properties 1))))

(defun my/org-image--identifier ()
  "Return the identifier attachments of this buffer are named after.
The Denote identifier of the file name when there is one, the
`#+identifier:' keyword next, and the file name itself as a last
resort, so the command also works in notes that are not Denote files."
  (let ((file (buffer-file-name)))
    (or (and file
             (fboundp 'denote-retrieve-filename-identifier)
             (denote-retrieve-filename-identifier file))
        (my/org-image--identifier-from-front-matter)
        (and file (my/org-image--slug (file-name-base file)))
        (format-time-string "%Y%m%dT%H%M%S"))))

(defun my/org-image--next-index (identifier slug)
  "Return the next free number for IDENTIFIER and SLUG, counting from 0.
The extension is ignored, so a PNG and a JPEG of the same note never
share a number even though the pipeline may pick different formats."
  (let* ((dir my/org-image-attachments-directory)
         (regexp (concat "\\`" (regexp-quote (format "%s--%s-" identifier slug))
                         "\\([0-9]+\\)\\."))
         (highest -1))
    (dolist (file (and (file-directory-p dir)
                       (directory-files dir nil regexp t)))
      (when (string-match regexp file)
        (setq highest (max highest (string-to-number (match-string 1 file))))))
    (1+ highest)))

(defun my/org-image--target (identifier slug extension)
  "Return the path of the next attachment for IDENTIFIER and SLUG."
  (let ((index (my/org-image--next-index identifier slug))
        (dir my/org-image-attachments-directory)
        (candidate nil))
    ;; The index comes from the numbers already in use; step past a name
    ;; that is somehow taken anyway rather than overwrite it.
    (while (progn
             (setq candidate
                   (expand-file-name
                    (format "%s--%s-%d.%s" identifier slug index extension)
                    dir))
             (file-exists-p candidate))
      (setq index (1+ index)))
    candidate))

;; ============================================================
;; CONVERTING
;; ============================================================

(defun my/org-image--magick ()
  "Return the ImageMagick executable to use, or nil when none is installed.
Version 7 installs `magick'; version 6 installs `convert', which
version 7 still ships as a deprecated alias -- hence the order."
  (or (executable-find "magick") (executable-find "convert")))

(defun my/org-image--size (file)
  "Return the size of FILE in bytes, or 0 when it is not there."
  (or (file-attribute-size (file-attributes file)) 0))

(defun my/org-image--run (args)
  "Run the converter with ARGS.  Return non-nil on success."
  (let ((magick (my/org-image--magick)))
    (and magick (eq 0 (apply #'call-process magick nil nil nil args)))))

(defun my/org-image--temp (extension)
  "Return a fresh temporary file name ending in EXTENSION."
  (make-temp-file "org-image-" nil (concat "." extension)))

(defun my/org-image--sampled-colors (file)
  "Return the number of distinct colours in a small sample of FILE.
`-sample' takes pixels as they are; `-resize' would blend them and
report millions of colours for a two-colour screenshot.  An unreadable
answer counts as `many', which routes the file to JPEG."
  (let ((magick (my/org-image--magick)))
    (with-temp-buffer
      (if (and magick
               (eq 0 (apply #'call-process magick nil t nil
                            (list file "-sample" "400x400"
                                  "-format" "%k" "info:")))
               (string-match "[0-9]+" (buffer-string)))
          (string-to-number (match-string 0 (buffer-string)))
        most-positive-fixnum))))

(defun my/org-image--compress (source no-resize)
  "Prepare a copy of SOURCE for storage.
Return a list (FILE EXTENSION METHOD).  FILE is either SOURCE itself or
a temporary file the caller must copy and then delete.  METHOD is a
symbol naming the last rung of the ladder that ran."
  (let ((ext (downcase (or (file-name-extension source) "png")))
        (budget my/org-image-max-bytes))
    (cond
     (no-resize (list source ext 'original))
     ((null (my/org-image--magick)) (list source ext 'no-converter))
     ((member ext my/org-image-no-resize-extensions) (list source ext 'verbatim))
     (t
      (let* ((resized (my/org-image--temp ext))
             (temps (list resized))
             (result
              (if (not (my/org-image--run
                        (append (list source "-auto-orient" "-strip")
                                (when my/org-image-max-pixels
                                  (list "-resize"
                                        (format "%dx%d>"
                                                my/org-image-max-pixels
                                                my/org-image-max-pixels)))
                                (list resized))))
                  ;; No delegate for this format, or a broken source.
                  (list source ext 'converter-failed)
                (if (or (null budget)
                        (<= (my/org-image--size resized) budget))
                    (list resized ext 'resized)
                  ;; Over budget: trade fidelity for size, cheapest
                  ;; trade first.
                  (let ((best resized)
                        (best-ext ext)
                        (best-method 'resized))
                    (when (<= (my/org-image--sampled-colors source)
                              my/org-image-palette-max-colors)
                      (let ((png8 (my/org-image--temp "png")))
                        (push png8 temps)
                        (when (and (my/org-image--run
                                    (list resized "-colors" "256"
                                          "-define" "png:compression-level=9"
                                          png8))
                                   (< (my/org-image--size png8)
                                      (my/org-image--size best)))
                          (setq best png8
                                best-ext "png"
                                best-method 'palette))))
                    (when (> (my/org-image--size best) budget)
                      (let ((jpeg (my/org-image--temp "jpg")))
                        (push jpeg temps)
                        (when (and (my/org-image--run
                                    (list resized
                                          "-background" "white"
                                          "-alpha" "remove" "-alpha" "off"
                                          "-quality"
                                          (number-to-string
                                           my/org-image-jpeg-quality)
                                          "-define"
                                          (format "jpeg:extent=%d" budget)
                                          jpeg))
                                   (< (my/org-image--size jpeg)
                                      (my/org-image--size best)))
                          (setq best jpeg
                                best-ext "jpg"
                                best-method 'jpeg))))
                    (list best best-ext best-method))))))
        (dolist (file temps)
          (unless (equal file (car result))
            (ignore-errors (delete-file file))))
        result)))))

(defun my/org-image--method-description (method)
  "Return what to tell the user about METHOD."
  (pcase method
    ('original         "stored unchanged (prefix argument)")
    ('no-converter     "stored unchanged: ImageMagick not found")
    ('verbatim         "stored unchanged: format not rescaled")
    ('converter-failed "stored unchanged: the converter refused it")
    ('resized          "rescaled")
    ('palette          "rescaled, 256-colour palette")
    ('jpeg             "rescaled, re-encoded as JPEG")
    (_                 "stored")))

;; ============================================================
;; INSERTING
;; ============================================================

(defun my/org-image--default-directory ()
  "Return the directory the file prompt should start in."
  (or my/org-image-source-directory
      (seq-find #'file-directory-p
                (list (expand-file-name "~/Pictures/")
                      (expand-file-name "~/Obrazy/")
                      (expand-file-name "~/Downloads/")
                      (expand-file-name "~/Pobrane/")))
      (expand-file-name "~/")))

(defun my/org-image--selectable-p (file)
  "Return non-nil when FILE is a directory or an image file."
  (or (file-directory-p file)
      (member (downcase (or (file-name-extension file) ""))
              my/org-image-extensions)))

(defun my/org-image--link-path (target)
  "Return the path to write into the link pointing at TARGET."
  (if (and (eq my/org-image-link-style 'relative) (buffer-file-name))
      (file-relative-name target (file-name-directory (buffer-file-name)))
    (abbreviate-file-name target)))

(defun my/org-image--preview-region (beg end)
  "Render inline previews between BEG and END.
Org 9.8 renamed `org-display-inline-images' to `org-link-preview-region'
and the argument lists differ, so each form is tried in turn; a version
that accepts neither leaves the preview to the next manual refresh."
  (or (ignore-errors
        (and (fboundp 'org-link-preview-region)
             (progn (org-link-preview-region nil beg end) t)))
      (ignore-errors
        (and (fboundp 'org-display-inline-images)
             (progn (org-display-inline-images nil t beg end) t))))
  (my/org-image--apply-keymap))

;;;###autoload
(defun my/org-image-insert (source name &optional no-resize)
  "Copy SOURCE into the attachment folder as NAME and link it at point.
NAME defaults to the note's title; the stored file is named after the
note's identifier and numbered from 0.  With a prefix argument,
NO-RESIZE stores the image exactly as it is."
  (interactive
   (progn
     (unless (derived-mode-p 'org-mode)
       (user-error "Images are inserted into Org buffers"))
     (let ((file (read-file-name "Image file: "
                                 (my/org-image--default-directory)
                                 nil t nil
                                 #'my/org-image--selectable-p))
           (default (or (my/org-image--note-title)
                        (and (buffer-file-name)
                             (file-name-base (buffer-file-name)))
                        "image")))
       (list file
             (if my/org-image-prompt-for-name
                 (read-string "Name in the attachment folder: " nil nil default)
               default)
             current-prefix-arg))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Images are inserted into Org buffers"))
  (unless (file-readable-p source)
    (user-error "Cannot read %s" source))
  (make-directory my/org-image-attachments-directory t)
  (let* ((before (my/org-image--size source))
         (prepared (my/org-image--compress source no-resize))
         (produced (nth 0 prepared))
         (extension (nth 1 prepared))
         (method (nth 2 prepared))
         (target (my/org-image--target (my/org-image--identifier)
                                       (my/org-image--slug name)
                                       extension)))
    (copy-file produced target t)
    (unless (equal produced source)
      (ignore-errors (delete-file produced)))
    (unless (bolp) (insert "\n"))
    (let ((beg (point)))
      (when my/org-image-attr-width
        (insert (format "#+ATTR_ORG: :width %s\n" my/org-image-attr-width)))
      (insert (format "[[file:%s]]\n" (my/org-image--link-path target)))
      (my/org-image--preview-region beg (point)))
    (message "%s  %s → %s  (%s)"
             (file-name-nondirectory target)
             (file-size-human-readable before)
             (file-size-human-readable (my/org-image--size target))
             (my/org-image--method-description method))))

;;;###autoload
(defun my/org-image-attachments-dired ()
  "Open the attachment folder in Dired."
  (interactive)
  (make-directory my/org-image-attachments-directory t)
  (dired my/org-image-attachments-directory))

;; ============================================================
;; ONE-OFF CLEANUP
;; ============================================================
;; For files stored before the budget existed, or before ImageMagick was
;; installed.  Names and extensions are preserved, so no link anywhere
;; has to change -- which also means a photograph stored as PNG is
;; quantised rather than turned into a JPEG, and may band.  Deleting
;; such a file and inserting it again gives a better result, since the
;; insertion path is free to choose the format.

;;;###autoload
(defun my/org-image-recompress-attachments ()
  "Shrink attachments larger than `my/org-image-max-bytes' in place.
Only PNG and JPEG files are touched, and only when the result is
actually smaller.  Names and extensions are preserved, so existing
links keep working."
  (interactive)
  (let* ((dir my/org-image-attachments-directory)
         (budget (or my/org-image-max-bytes
                     (user-error "`my/org-image-max-bytes' is nil")))
         (files (and (file-directory-p dir)
                     (seq-filter
                      (lambda (file)
                        (and (member (downcase (or (file-name-extension file) ""))
                                     '("png" "jpg" "jpeg"))
                             (> (my/org-image--size file) budget)))
                      (directory-files dir t "\\`[^.]" t))))
         (before 0)
         (after 0)
         (changed 0))
    (cond
     ((null (my/org-image--magick))
      (user-error "ImageMagick not found"))
     ((null files)
      (message "Nothing over %s in %s"
               (file-size-human-readable budget) dir))
     ((yes-or-no-p
       (format "Recompress %d file(s), %s in total, in place? "
               (length files)
               (file-size-human-readable
                (apply #'+ (mapcar #'my/org-image--size files)))))
      (dolist (file files)
        (let* ((ext (downcase (file-name-extension file)))
               (temp (my/org-image--temp ext))
               (jpeg (member ext '("jpg" "jpeg")))
               (size (my/org-image--size file)))
          (setq before (+ before size))
          (when (and (my/org-image--run
                      (append (list file "-auto-orient" "-strip")
                              (when my/org-image-max-pixels
                                (list "-resize"
                                      (format "%dx%d>"
                                              my/org-image-max-pixels
                                              my/org-image-max-pixels)))
                              (if jpeg
                                  (list "-quality"
                                        (number-to-string
                                         my/org-image-jpeg-quality)
                                        "-define"
                                        (format "jpeg:extent=%d" budget))
                                (list "-colors" "256"
                                      "-define" "png:compression-level=9"))
                              (list temp)))
                     (> (my/org-image--size temp) 0)
                     (< (my/org-image--size temp) size))
            (copy-file temp file t)
            (setq changed (1+ changed)))
          (ignore-errors (delete-file temp))
          (setq after (+ after (my/org-image--size file)))))
      (message "Recompressed %d of %d file(s): %s → %s"
               changed (length files)
               (file-size-human-readable before)
               (file-size-human-readable after))))))

;; ============================================================
;; OPENING A PREVIEW
;; ============================================================

(defun my/org-image--file-at (pos)
  "Return the image file displayed or linked at POS, or nil.
The overlay's own image specification is asked first, so this works
whatever link syntax produced the preview; the Org element is the
fallback for a link whose preview is not currently shown."
  (let ((display (get-char-property pos 'display)))
    (or (and (consp display)
             (eq (car display) 'image)
             (plist-get (cdr display) :file))
        (save-excursion
          (goto-char pos)
          (let ((context (org-element-context)))
            (when (and (eq (org-element-type context) 'link)
                       (equal (org-element-property :type context) "file"))
              (expand-file-name (org-element-property :path context))))))))

(defun my/org-image--open-externally (file)
  "Hand FILE to the desktop image viewer."
  (let ((opener (executable-find "xdg-open")))
    (if opener
        (start-process "org-image-open" nil opener (expand-file-name file))
      (org-open-file file 'system))))

(defun my/org-image--open (file &optional how)
  "Open FILE, in Emacs or externally according to HOW."
  (cond
   ((not (file-exists-p file))
    (user-error "Missing attachment: %s" file))
   ((eq how 'external) (my/org-image--open-externally file))
   (t (find-file-other-window file))))

(defun my/org-image-open-at-point ()
  "Open the image at point."
  (interactive)
  (my/org-image--open (or (my/org-image--file-at (point))
                          (user-error "No image at point"))
                      my/org-image-click-action))

(defun my/org-image-open-externally-at-point ()
  "Open the image at point in the desktop image viewer."
  (interactive)
  (my/org-image--open (or (my/org-image--file-at (point))
                          (user-error "No image at point"))
                      'external))

(defun my/org-image-mouse-open (event)
  "Open the image clicked on by EVENT.
A click that lands on something other than an image only moves point,
so the binding never swallows an ordinary click."
  (interactive "e")
  (let* ((pos (posn-point (event-end event)))
         (file (and pos (my/org-image--file-at pos))))
    (if file
        (my/org-image--open file my/org-image-click-action)
      (mouse-set-point event))))

(defvar my/org-image-map
  (let ((map (make-sparse-keymap)))
    (when (boundp 'image-map)
      (set-keymap-parent map image-map))
    (define-key map [mouse-1] #'my/org-image-mouse-open)
    (define-key map (kbd "RET") #'my/org-image-open-at-point)
    (define-key map (kbd "x") #'my/org-image-open-externally-at-point)
    map)
  "Keymap placed on inline image overlays in Org buffers.
Inherits `image-map', so the scaling and saving commands Emacs already
provides there (`i +', `i -', `i o') keep working.")

(defun my/org-image--apply-keymap (&rest _)
  "Put `my/org-image-map' on every inline image overlay in the buffer.
Run after Org has created the previews; the overlays it makes carry
`image-map', which has no binding for a click."
  (when (and my/org-image-click-action
             (derived-mode-p 'org-mode))
    (dolist (ov (overlays-in (point-min) (point-max)))
      (let ((display (overlay-get ov 'display)))
        (when (and (consp display)
                   (eq (car display) 'image)
                   (not (eq (overlay-get ov 'keymap) my/org-image-map)))
          (overlay-put ov 'keymap my/org-image-map))))))

;; Both names are advised: Org up to 9.7 displays previews through
;; `org-display-inline-images', 9.8 through `org-link-preview-region',
;; and where one is an alias of the other the work is idempotent.
(dolist (fn '(org-link-preview-region org-display-inline-images))
  (when (fboundp fn)
    (advice-add fn :after #'my/org-image--apply-keymap)))

;; ============================================================
;; MENU
;; ============================================================
;; Appended to the Insert submenu after "w" (Well-being).  Skipped
;; without complaint when 12-transient.el is not loaded.

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-insert-menu "w"
                       '("i" "Image from disk" my/org-image-insert))
  (my/transient-append 'my/notes-insert-menu "i"
                       '("I" "Attachments folder" my/org-image-attachments-dired)))

(provide '31-org-images)
;;; 31-org-images.el ends here
