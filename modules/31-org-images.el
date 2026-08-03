;;; 31-org-images.el --- Image attachments for notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Pick an image from disk, downscale it, park it in ~/notes/attachments/
;; under the identifier of the note it is inserted into, and link it at
;; point.  Clicking the inline preview opens the file at full size.
;;
;; Entry points:
;;
;;   `my/org-image-insert'             C-c n i i
;;   `my/org-image-attachments-dired'  C-c n i I
;;   mouse-1 / RET on a preview        open the image
;;   x on a preview                    open it in the desktop viewer
;;
;; WHY THE FILE NAME CARRIES THE NOTE IDENTIFIER
;;
;; An attachment folder without a naming rule becomes unreadable within
;; a year: several hundred files called IMG_2451.jpg with nothing to say
;; which note wanted them.  Naming each copy
;;
;;   20260803T121500--wykres-inflacji.png
;;
;; puts every attachment of one note next to its siblings in a sorted
;; listing, and makes an orphan obvious -- an identifier with no note
;; behind it is a file nothing refers to any more.
;;
;; The identifier is the NOTE's, not a fresh one.  That is the whole
;; point, and it is also why the attachment folder must stay out of
;; Denote's way: two files sharing an identifier is exactly what
;; 27-denote-identifiers.el exists to report.  It only ever reads .org
;; files, so images are invisible to it, but Denote's own prompts and
;; backlink buffers walk the whole tree.  This module therefore adds the
;; folder to `denote-excluded-directories-regexp' -- extending, never
;; replacing, the value 25-inbox-review.el sets for the staging inbox.
;; Removing this module removes the exclusion with it, which is correct:
;; without the module there is no attachment folder to hide.
;;
;; WHY THE COPY IS DOWNSCALED
;;
;; A phone photograph is 3-4 thousand pixels wide and several megabytes.
;; Nothing in a note needs that: it is displayed at around a thousand
;; pixels, exported at less, and Syncthing copies every byte of it to
;; every device.  `my/org-image-max-pixels' caps the longer edge on the
;; way in.  This is a one-off conversion of the stored file, not a
;; display setting -- display width is `org-image-actual-width', owned by
;; 11-org-appearance.el, and the two are related only in that there is no
;; point storing many more pixels than are ever shown.
;;
;; Downscaling needs ImageMagick (`magick', or `convert' on version 6) on
;; PATH.  Without it the file is copied unchanged and a message says so;
;; nothing fails.  On NixOS, add `imagemagick' to the system packages.
;;
;; WHY CLICKING OPENS THE FILE INSTEAD OF GROWING THE PREVIEW
;;
;; Org's inline preview is one scaled bitmap held in an overlay.  Growing
;; it in place is possible -- `image-increase-size', which Emacs already
;; binds under `i +' in `image-map' -- but it rescales the same overlay
;; inside a text buffer, reflowing everything below it, and the enlarged
;; size is lost on the next image refresh.  Opening the file gives the
;; full resolution in a buffer (or viewer) built for looking at images,
;; with panning and zooming that already work.  `image-map' stays
;; reachable as the parent keymap, so `i +' still does what it did.
;;
;; DEPENDENCIES
;;
;; Org is required.  Denote is optional and only supplies the identifier;
;; without it the note's file name is used instead.  ImageMagick is
;; optional, as described above.  12-transient.el is optional: the menu
;; entries go through `my/transient-append', which reports and skips when
;; the menu or the helper is absent.
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
Images are never enlarged: a source smaller than this is copied as it
is.  Set to nil to store every image at its original resolution."
  :type '(choice (const :tag "Do not resize" nil) integer)
  :group 'my)

(defcustom my/org-image-jpeg-quality 85
  "JPEG quality of rescaled attachments, 1-100."
  :type 'integer
  :group 'my)

(defcustom my/org-image-no-resize-extensions '("svg" "svgz" "gif")
  "Extensions never passed through the rescaler.
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
;; See the commentary.  The base value belongs to 25-inbox-review.el and
;; is extended here, never overwritten; running this twice is harmless.

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
resort so that the command also works in notes that are not Denote
files at all."
  (let ((file (buffer-file-name)))
    (or (and file
             (fboundp 'denote-retrieve-filename-identifier)
             (denote-retrieve-filename-identifier file))
        (my/org-image--identifier-from-front-matter)
        (and file (my/org-image--slug (file-name-base file)))
        (format-time-string "%Y%m%dT%H%M%S"))))

(defun my/org-image--unique-target (identifier slug extension)
  "Return an unused path IDENTIFIER--SLUG.EXTENSION in the attachment folder."
  (let* ((base (format "%s--%s" identifier slug))
         (dir my/org-image-attachments-directory)
         (candidate (expand-file-name (concat base "." extension) dir))
         (n 1))
    (while (file-exists-p candidate)
      (setq candidate (expand-file-name (format "%s-%d.%s" base n extension) dir)
            n (1+ n)))
    candidate))

;; ============================================================
;; COPY AND RESCALE
;; ============================================================

(defun my/org-image--magick ()
  "Return the ImageMagick executable to use, or nil when none is installed.
Version 7 installs `magick'; version 6 installs `convert'."
  (or (executable-find "magick") (executable-find "convert")))

(defun my/org-image--install (source target &optional no-resize)
  "Copy SOURCE to TARGET, downscaling on the way when that is possible.
Return non-nil when the copy was rescaled.  Any failure of the external
converter falls back to a plain copy: a format ImageMagick has no
delegate for should still end up in the note."
  (let* ((ext (downcase (or (file-name-extension source) "")))
         (magick (my/org-image--magick))
         (rescale (and (not no-resize)
                       magick
                       my/org-image-max-pixels
                       (not (member ext my/org-image-no-resize-extensions)))))
    (cond
     ((not rescale)
      (copy-file source target t)
      nil)
     (t
      ;; The trailing ">" means "only shrink"; without a shell around it
      ;; the character needs no quoting.
      (let* ((geometry (format "%dx%d>"
                               my/org-image-max-pixels
                               my/org-image-max-pixels))
             (args (append (list source "-auto-orient" "-strip"
                                 "-resize" geometry)
                           (when (member ext '("jpg" "jpeg"))
                             (list "-quality"
                                   (number-to-string my/org-image-jpeg-quality)))
                           (list target)))
             (status (apply #'call-process magick nil nil nil args)))
        (if (and (eq status 0) (file-exists-p target))
            t
          (copy-file source target t)
          nil))))))

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
and the argument lists differ, so each form is tried in turn and a
version that accepts neither simply leaves the preview to the next
manual refresh."
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
The copy is named after the identifier of the current note, and its
longer edge is capped at `my/org-image-max-pixels'.  With a prefix
argument, NO-RESIZE keeps the original resolution."
  (interactive
   (progn
     (unless (derived-mode-p 'org-mode)
       (user-error "Images are inserted into Org buffers"))
     (let ((file (read-file-name "Image file: "
                                 (my/org-image--default-directory)
                                 nil t nil
                                 #'my/org-image--selectable-p)))
       (list file
             (read-string "Name in the attachment folder: "
                          nil nil (file-name-base file))
             current-prefix-arg))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Images are inserted into Org buffers"))
  (unless (file-readable-p source)
    (user-error "Cannot read %s" source))
  (make-directory my/org-image-attachments-directory t)
  (let* ((ext (downcase (or (file-name-extension source) "png")))
         (target (my/org-image--unique-target (my/org-image--identifier)
                                              (my/org-image--slug name)
                                              ext))
         (rescaled (my/org-image--install source target no-resize)))
    (unless (bolp) (insert "\n"))
    (let ((beg (point)))
      (when my/org-image-attr-width
        (insert (format "#+ATTR_ORG: :width %s\n" my/org-image-attr-width)))
      (insert (format "[[file:%s]]\n" (my/org-image--link-path target)))
      (my/org-image--preview-region beg (point)))
    (message "%s → %s%s"
             (file-name-nondirectory source)
             (file-name-nondirectory target)
             (cond (rescaled (format " (capped at %d px)"
                                     my/org-image-max-pixels))
                   ((and my/org-image-max-pixels
                         (not no-resize)
                         (not (my/org-image--magick)))
                    " (copied unchanged: ImageMagick not found)")
                   (t "")))))

;;;###autoload
(defun my/org-image-attachments-dired ()
  "Open the attachment folder in Dired."
  (interactive)
  (make-directory my/org-image-attachments-directory t)
  (dired my/org-image-attachments-directory))

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
