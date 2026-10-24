;;; 48-settings-tools.el --- Favourite and recently changed settings -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes

;;; Commentary:
;; Two ways back to a setting without searching the tree for it:
;;
;;   C-c n , *   favourite settings: a Customize buffer of one's own
;;   C-c n , +   add a setting to the favourites (the one at point in a
;;               Customize buffer, or chosen by name)
;;   C-c n , -   remove one
;;   C-c n , r   recently changed settings, newest first, in a Customize
;;               buffer: each with its own State menu to revert it
;;   C-c n , z   undo one recent change: back to the value it had before
;;
;; FAVOURITES are an option, `my/settings-favourites', so they are saved
;; with this machine's settings like everything else.
;;
;; RECENT CHANGES are recorded whenever a variable is set or saved
;; through Customize -- in a Customize buffer, or by
;; `customize-set-variable' / `customize-save-variable' from code --
;; with the time and the value it had before.  Kept in the settings
;; folder of this machine (recent-settings.eld), the newest
;; `my/settings-recent-max' entries, so they survive a restart, which
;; Customize's own "Revert This Session's Customization" does not.
;; Values that cannot be written and read back (a closure, a buffer) are
;; recorded without the old value; undo then says so.
;;
;; RELATION TO OTHER MODULES
;; - 00-core.el: `my/host-directory' (where the record is kept) and
;;   `my/settings-apply-on-set'.  Without them the record lives in
;;   ~/.emacs.d.
;; - 12-transient.el: the entries are appended to `my/settings-menu' with
;;   `my/transient-append'; without it the commands are M-x only.
;;
;; Docs: ~/.emacs.d/function_helper.org::#settings-favourites

;;; Code:

(require 'cus-edit)
(require 'seq)
(require 'subr-x)

(defgroup my/settings-tools nil
  "Favourite and recently changed settings (48-settings-tools.el)."
  :tag "Favourites and recent changes"
  :group 'mypks)

(defcustom my/settings-favourites nil
  "Settings shown together by `my/settings-favourites-open' (C-c n , *).
A list of variable names, in the order they are shown."
  :type '(repeat (variable :tag "Setting"))
  :tag "Favourite settings"
  :group 'my/settings-tools)

(defcustom my/settings-recent-max 20
  "How many recently changed settings are remembered."
  :type 'integer
  :tag "Recent changes remembered"
  :group 'my/settings-tools)

;; ============================================================
;; FAVOURITES
;; ============================================================

(defvar custom-options)

(defun my/settings--variable-widget-at (pos widgets)
  "Return the custom-variable widget among WIDGETS spanning POS, or nil.
Searches children too: in a group buffer the variables are children of
the group.  The tag and documentation of an entry are plain text, so
`widget-at' alone finds nothing there."
  (seq-some (lambda (w)
              (let ((from (widget-get w :from)) (to (widget-get w :to)))
                (when (and from to (<= from pos) (<= pos to))
                  (if (eq (widget-type w) 'custom-variable)
                      w
                    (my/settings--variable-widget-at pos (widget-get w :children))))))
            widgets))

(defun my/settings--option-at-point ()
  "Return the variable of the Customize entry at point, or nil."
  (when (derived-mode-p 'Custom-mode)
    (let ((widget (my/settings--variable-widget-at (point) custom-options)))
      (when widget (widget-value widget)))))

(defun my/settings--read-option (prompt &optional candidates)
  "Ask with PROMPT for a variable; CANDIDATES limits the choice.
Defaults to the Customize entry at point."
  (let ((default (my/settings--option-at-point)))
    (intern (completing-read
             (if default (format "%s (default %s): " prompt default) (concat prompt ": "))
             (or candidates
                 (let (all)
                   (mapatoms (lambda (s) (when (custom-variable-p s) (push s all))))
                   all))
             nil t nil nil (and default (symbol-name default))))))

(defun my/settings-favourite-add (option)
  "Add OPTION to the favourite settings, and save them."
  (interactive (list (my/settings--read-option "Add to favourites")))
  (if (memq option my/settings-favourites)
      (message "%s is already a favourite" option)
    (customize-save-variable 'my/settings-favourites
                             (append my/settings-favourites (list option)))
    (message "%s added to the favourite settings (C-c n , *)" option)))

(defun my/settings-favourite-remove (option)
  "Remove OPTION from the favourite settings, and save them."
  (interactive
   (progn
     (unless my/settings-favourites (user-error "No favourite settings yet"))
     (list (my/settings--read-option "Remove from favourites"
                                     (mapcar #'symbol-name my/settings-favourites)))))
  (customize-save-variable 'my/settings-favourites (delq option (copy-sequence my/settings-favourites)))
  (message "%s removed from the favourite settings" option))

(defun my/settings-favourites-open ()
  "Show the favourite settings in one Customize buffer."
  (interactive)
  (let ((options (seq-filter #'boundp my/settings-favourites)))
    (unless options
      (user-error "No favourite settings yet: C-c n , + on a setting adds it"))
    (custom-buffer-create (mapcar (lambda (s) (list s 'custom-variable)) options)
                          "*MyPKS favourite settings*")))

;; ============================================================
;; RECENT CHANGES
;; ============================================================

(defun my/settings--recent-file ()
  "Return the file holding the record of recent changes."
  (expand-file-name "recent-settings.eld"
                    (if (boundp 'my/host-directory) my/host-directory user-emacs-directory)))

(defun my/settings--recent-read-file (file)
  "Return the records in FILE, or the symbol `unreadable' when it has none."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (let ((data (read (current-buffer))))
          (if (listp data) data 'unreadable)))
    (error 'unreadable)))

(defun my/settings--recent-read ()
  "Return the recorded changes, newest first: plists (:option :time :old)."
  (let ((file (my/settings--recent-file)))
    (when (file-readable-p file)
      (let ((data (my/settings--recent-read-file file)))
        (unless (eq data 'unreadable) data)))))

(defun my/settings--recent-set-aside ()
  "Keep an unreadable record file under its own name; return that name.
Until 2026-10-24 a record that could not be read counted as empty, and
the next change overwrote it: the history was gone without a word
(found by the tests of this module)."
  (let ((file (my/settings--recent-file)))
    (when (and (file-readable-p file)
               (eq (my/settings--recent-read-file file) 'unreadable))
      (let ((aside (concat file ".unreadable")))
        (rename-file file aside t)
        (message "Settings record could not be read; kept as %s" aside)
        aside))))

(defun my/settings--printable-p (value)
  "Non-nil when VALUE can be written and read back as the same value."
  (condition-case nil
      (equal value (car (read-from-string (prin1-to-string value))))
    (error nil)))

(defvar my/settings--recording nil
  "Non-nil while a change is being recorded, so that nested sets are not.")

(defun my/settings--record (option old)
  "Record that OPTION changed from OLD, now."
  (unless (or my/settings--recording
              (eq option 'my/settings-favourites))
    (let* ((my/settings--recording t)
           (entry (append (list :option option
                                :time (format-time-string "%Y-%m-%d %H:%M"))
                          (when (my/settings--printable-p old) (list :old old))))
           (records (cons entry (seq-remove (lambda (e) (eq (plist-get e :option) option))
                                            (my/settings--recent-read)))))
      (when (> (length records) my/settings-recent-max)
        (setq records (seq-take records my/settings-recent-max)))
      (condition-case err
          (let* ((file (my/settings--recent-file))
                 (partial (concat file ".partial")))
            (my/settings--recent-set-aside)
            ;; Written under another name and renamed when complete, so
            ;; a write cut short never stands in for the record.
            (with-temp-file partial
              (insert ";; Written by 48-settings-tools.el: recently changed settings.\n")
              (let ((print-length nil) (print-level nil))
                (prin1 records (current-buffer)))
              (insert "\n"))
            (rename-file partial file t))
        (error (message "Settings record not written: %s" (error-message-string err)))))))

(defun my/settings--record-widget (fn widget &rest args)
  "Around a Customize buffer's set or save: record the change of WIDGET.
FN is `custom-variable-set' or `custom-variable-mark-to-save'; ARGS its
other arguments."
  (let* ((option (widget-value widget))
         (old (and (boundp option) (default-value option))))
    (prog1 (apply fn widget args)
      (when (and (boundp option) (not (equal old (default-value option))))
        (my/settings--record option old)))))

(defun my/settings--record-call (fn option value &rest args)
  "Around `customize-set-variable' and `customize-save-variable': record.
FN is the function, OPTION and VALUE its arguments, ARGS the rest."
  (let ((old (and (boundp option) (default-value option)))
        (changed (not (and (boundp option) (equal value (default-value option))))))
    (prog1 (apply fn option value args)
      (when changed
        (my/settings--record option old)))))

(advice-add 'custom-variable-set :around #'my/settings--record-widget)
(advice-add 'custom-variable-mark-to-save :around #'my/settings--record-widget)
(advice-add 'customize-set-variable :around #'my/settings--record-call)
(advice-add 'customize-save-variable :around #'my/settings--record-call)

(defun my/settings-recent-open ()
  "Show the recently changed settings, newest first, in a Customize buffer.
Each entry has its State menu, which reverts or saves it."
  (interactive)
  (let ((options (seq-filter #'boundp
                             (mapcar (lambda (e) (plist-get e :option))
                                     (my/settings--recent-read)))))
    (unless options
      (user-error "No setting changed since this record began"))
    (custom-buffer-create (mapcar (lambda (s) (list s 'custom-variable)) options)
                          "*MyPKS recently changed settings*")
    (message "Newest first: %s"
             (mapconcat (lambda (e) (format "%s (%s)" (plist-get e :option) (plist-get e :time)))
                        (seq-take (my/settings--recent-read) 3) ", "))))

(defun my/settings-recent-undo (option)
  "Set OPTION back to the value it had before its last recorded change.
Saved when the option has a saved value, else only set."
  (interactive
   (let* ((records (my/settings--recent-read))
          (labels (mapcar (lambda (e)
                            (cons (format "%s  %s  (was %s)"
                                          (plist-get e :time) (plist-get e :option)
                                          (if (plist-member e :old)
                                              (truncate-string-to-width
                                               (prin1-to-string (plist-get e :old)) 40 nil nil "...")
                                            "not recorded"))
                                  (plist-get e :option)))
                          records)))
     (unless records (user-error "No setting changed since this record began"))
     (list (cdr (assoc (completing-read "Undo the change of: " labels nil t) labels)))))
  (let ((entry (seq-find (lambda (e) (eq (plist-get e :option) option))
                         (my/settings--recent-read))))
    (unless (plist-member entry :old)
      (user-error "The old value of %s was not recorded (not printable)" option))
    (let ((old (plist-get entry :old)))
      (if (get option 'saved-value)
          (customize-save-variable option old)
        (customize-set-variable option old))
      (message "%s is back to %s" option
               (truncate-string-to-width (prin1-to-string old) 60 nil nil "...")))))

;; ============================================================
;; MENU
;; ============================================================

(with-eval-after-load '12-transient
  (when (fboundp 'my/transient-append)
    ;; Anchored on "f", which belongs to 12-transient's settings menu.
    (my/transient-append 'my/settings-menu "u"
                         '("*" "Favourite settings" my/settings-favourites-open))
    (my/transient-append 'my/settings-menu "*"
                         '("+" "Add a setting to favourites" my/settings-favourite-add))
    (my/transient-append 'my/settings-menu "+"
                         '("-" "Remove from favourites" my/settings-favourite-remove))
    (my/transient-append 'my/settings-menu "-"
                         '("r" "Recently changed settings" my/settings-recent-open))
    (my/transient-append 'my/settings-menu "r"
                         '("z" "Undo a recent change" my/settings-recent-undo))))

(provide '48-settings-tools)
;;; 48-settings-tools.el ends here
