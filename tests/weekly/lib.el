;;; lib.el --- Shared code of the weekly checks: loading, snapshots, child runs -*- lexical-binding: t; -*-

;;; Commentary:

;; The weekly checks (hooks/check-weekly, .github/workflows/weekly.yml)
;; need every package of the configuration installed; the checks run on
;; every push (hooks/check-all) do not.  This file is what they share:
;;
;; - `my/weekly-modules': the modules init.el loads, in its order, read
;;   from init.el's (my/modules-load '(...)) list;
;; - `my/weekly-start': the sandbox of tests/helper.el, 000-core.el loaded,
;;   the modules read from this repository, none turned off;
;; - `my/weekly-snapshot': what a module can leave behind -- hooks,
;;   advice, key bindings, repeating timers, menu entries, file-name and
;;   magic mode lists, capture templates, global minor modes -- as a
;;   multiset of strings;
;; - the three runs a child Emacs makes for test-modules.el, each
;;   printing PROBLEM lines (the parent's failure) and INFO lines.
;;
;; Not a test file: hooks/check-all runs tests/test-*.el only.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst my/weekly-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "This folder, tests/weekly/.")

(load (expand-file-name "../helper" my/weekly-directory) nil t)

(defun my/weekly-modules ()
  "Return the modules of init.el's list for `my/modules-load', in order."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" my/test-repo))
    (goto-char (point-min))
    (unless (re-search-forward "(my/modules-load\\s-*'" nil t)
      (error "init.el has no (my/modules-load '(...)) list"))
    (read (current-buffer))))

(defun my/weekly-start ()
  "Enter the sandbox and load 000-core.el; every module may load.
The modules are read from this repository; `my/modules-off' is emptied,
since a new machine would otherwise leave out the modules marked
\"MyPKS-Default: off\" -- these checks are about every module."
  (my/test-load-modules)
  (setq my/modules-directory (expand-file-name "modules/" my/test-repo))
  (clrhash my/modules--info-cache)
  (setq my/modules-off nil)
  (setq my/modules-order (cons "000-core" (my/weekly-modules))))

(defun my/weekly-problem (format-string &rest args)
  "Print a PROBLEM line: the parent test fails and shows it."
  (princ (concat "PROBLEM " (apply #'format format-string args) "\n")))

(defun my/weekly-info (format-string &rest args)
  "Print an INFO line, shown by the parent only in verbose runs."
  (princ (concat "INFO " (apply #'format format-string args) "\n")))

(defun my/weekly-load (names)
  "Load NAMES with the loader of 000-core.el; report every module not loaded."
  (my/modules-load names)
  (dolist (entry my/modules--skipped)
    (my/weekly-problem "%s" (my/modules--skip-line entry))))

;; ============================================================
;; SNAPSHOTS
;; ============================================================

(defun my/weekly--fn (f)
  "A stable name for the function F in a snapshot."
  (cond ((symbolp f) (symbol-name f))
        ((byte-code-function-p f) "<compiled lambda>")
        ((functionp f) "<lambda>")
        (t (format "%S" f))))

(defun my/weekly--binding (b)
  "A stable name for the key binding B, or nil for a prefix keymap."
  (cond ((null b) nil)                  ; unbound: `keymap-unset', (define-key MAP KEY nil)
        ((symbolp b) (symbol-name b))
        ((keymapp b) nil)
        ((stringp b) (format "%S" b))
        ((vectorp b) (format "%S" b))
        ((and (consp b) (eq (car b) 'menu-item))
         (format "menu-item %s" (my/weekly--binding (nth 2 b))))
        ((and (consp b) (stringp (car b)))   ; (STRING . DEFN), old menus
         (my/weekly--binding (cdr b)))
        ((functionp b) "<lambda>")
        (t (format "%S" b))))

(defun my/weekly--keys (map prefix depth seen add)
  "Call ADD with each binding of MAP under PREFIX, its own, not its parent's."
  (unless (or (> depth 6) (memq map seen))
    (push map seen)
    (map-keymap-internal
     (lambda (event b)
       (let ((keys (vconcat prefix (vector event)))
             (sub (cond ((keymapp b) b)
                        ((and (consp b) (eq (car b) 'menu-item) (keymapp (nth 2 b)))
                         (nth 2 b)))))
         ;; A prefix bound by name is followed to its keymap; one not
         ;; loaded yet (an autoload) is recorded by name.
         (when (symbolp sub)
           (setq sub (and (keymapp (indirect-function sub)) (indirect-function sub))))
         (if (and sub (not (and (symbolp b) (commandp b))))
             (my/weekly--keys sub keys (1+ depth) seen add)
           (let ((name (my/weekly--binding b)))
             (when name
               (funcall add (format "%s %s" (key-description keys) name)))))))
     map)))

(defun my/weekly--menu-entries (layout add)
  "Call ADD with KEY COMMAND for each entry in the transient LAYOUT.
Reads every shape transient has used: lists, vectors, (CLASS . PLIST)."
  (cond ((vectorp layout) (my/weekly--menu-entries (append layout nil) add))
        ((consp layout)
         (when (proper-list-p layout)
           (let ((command (plist-get (seq-drop-while (lambda (x) (not (keywordp x))) layout)
                                     :command)))
             (when command
               (funcall add (format "%s %s"
                                    (plist-get (seq-drop-while (lambda (x) (not (keywordp x))) layout)
                                               :key)
                                    (my/weekly--fn command))))))
         (dolist (x (if (proper-list-p layout) layout (list (car layout) (cdr layout))))
           (when (or (consp x) (vectorp x))
             (my/weekly--menu-entries x add))))))

(defun my/weekly-snapshot ()
  "Return what loaded code can leave behind: a hash table, item -> count."
  (let ((items (make-hash-table :test #'equal)))
    (cl-flet ((add (item) (puthash item (1+ (gethash item items 0)) items)))
      (mapatoms
       (lambda (s)
         (let ((n (symbol-name s)))
           (when (and (boundp s) (default-boundp s)
                      (string-match-p "-\\(hook\\|hooks\\|functions\\)\\'" n))
             (let ((v (default-value s)))
               (when (and (consp v) (not (functionp v)) (proper-list-p v))
                 (dolist (f v)
                   (unless (eq f t)
                     (add (format "hook %s: %s" n (my/weekly--fn f))))))))
           (when (fboundp s)
             (advice-mapc (lambda (f _props) (add (format "advice %s: %s" n (my/weekly--fn f))))
                          s))
           (when (and (boundp s) (default-boundp s) (string-suffix-p "-map" n)
                      (keymapp (default-value s)))
             (my/weekly--keys (default-value s) [] 0 nil
                              (lambda (k) (add (format "key %s: %s" n k)))))
           (when (get s 'transient--layout)
             (my/weekly--menu-entries (get s 'transient--layout)
                                      (lambda (e) (add (format "menu %s: %s" n e))))))))
      (dolist (timer (append timer-list timer-idle-list))
        (when (timer--repeat-delay timer)
          (add (format "timer %s" (my/weekly--fn (timer--function timer))))))
      (dolist (entry auto-mode-alist)
        (add (format "auto-mode %S" entry)))
      (dolist (entry magic-mode-alist)
        (add (format "magic-mode %S" entry)))
      (when (boundp 'org-capture-templates)
        (dolist (template org-capture-templates)
          (add (format "capture %S %S" (car template) (cadr template)))))
      (dolist (mode global-minor-modes)
        (add (format "global-mode %s" mode))))
    items))

(defun my/weekly-names ()
  "Return a hash table of the names of this configuration's symbols now
bound, defined or holding a menu: what existed before a module loaded."
  (let ((names (make-hash-table :test #'equal)))
    (mapatoms (lambda (s)
                (let ((n (symbol-name s)))
                  (when (and (string-prefix-p "my/" n)
                             (or (boundp s) (fboundp s) (get s 'transient--layout)))
                    (puthash n t names)))))
    names))

(defun my/weekly-new-container-p (item names)
  "Non-nil when ITEM lies in a hook, keymap, menu or function of this
configuration that is not in NAMES, the names existing before the module
loaded: the module's own definitions (its menus, its modes' keymaps), or
a hook of a module loaded after it.  Rule 12 of the module contract
asks the switch to take back what the module puts into what exists
already; what it defines stays, as its commands do."
  (and (string-match "\\`\\(?:hook\\|key\\|menu\\|advice\\) \\(my/[^ :]+\\):" item)
       (not (gethash (match-string 1 item) names))))

(defun my/weekly-difference (a b)
  "Items of snapshot A not in B, or more often in A: a sorted list."
  (let (out)
    (maphash (lambda (item count)
               (let ((extra (- count (gethash item b 0))))
                 (when (> extra 0)
                   (push (if (> extra 1) (format "%s (x%d)" item extra) item) out))))
             a)
    (sort out #'string<)))

;; ============================================================
;; THE RUNS OF A CHILD EMACS
;; ============================================================

(defun my/weekly--with-requirements (name)
  "NAME and every module it requires, in init.el's order."
  (let ((wanted (cons name (my/modules--requirements name))))
    (seq-filter (lambda (n) (member n wanted)) (cdr my/modules-order))))

(defun my/weekly-run-alone (name)
  "Load 000-core.el, the modules NAME requires and NAME, nothing else.
A module that uses another without declaring it in MyPKS-Requires fails
here -- unless the use is guarded, which is what the contract asks."
  (my/weekly-start)
  (my/weekly-load (my/weekly--with-requirements name))
  (my/weekly-info "loaded: %s" (string-join (cdr my/modules-loaded) " ")))

(defun my/weekly-run-without (name)
  "Load every module except NAME and the modules that require it.
Every one of them must load: none may need NAME without saying so."
  (my/weekly-start)
  (let ((out (cons name (my/modules--dependants name (cdr my/modules-order)))))
    (my/weekly-info "left out: %s" (string-join out " "))
    (my/weekly-load (seq-remove (lambda (n) (member n out)) (cdr my/modules-order)))))

(defun my/weekly-own-p (item)
  "Non-nil when snapshot ITEM can come from this configuration's code.
Loading a module loads its packages, and they bring keymaps, hooks and
menus of their own that no switch can take back (Emacs does not unload
a package; function_helper.org, \"A module's switch\").  So an item
left after the switch is off counts when it names a symbol of this
configuration (my/...), or is a global key, a repeating timer, a mode
list entry, a capture template or a global minor mode -- what a package
does not set merely by being loaded."
  (or (string-match-p "my/" item)
      ;; A nameless function in a hook or advice: packages rarely add
      ;; one at load, and the contract asks a module to name its own.
      (string-match-p "\\`\\(hook\\|advice\\) [^:]+: <\\(compiled \\)?lambda>" item)
      (string-match-p "\\`\\(key global-map: \\|timer \\|auto-mode \\|magic-mode \\|capture \\|global-mode \\)"
                      item)))

(defvar my/weekly-allowed-leftovers
  '(;; 207-git: a module's folders stay in the automatic commits when it is
    ;; off (function_helper.org, "A module's switch": the one exception).
    "^hook my/auto-commit-repository-sources-functions: ")
  "Regexps of items a switched-off module may leave, by decision.")

(defun my/weekly-run-switch (name)
  "Switch NAME off and on again, after every other module has loaded.
Before: everything but NAME and its dependants.  After loading NAME and
switching it off, the snapshot must equal the one before -- nothing
left behind, nothing of another module removed.  Switched on again, it
must equal the one taken when NAME was first on -- nothing doubled."
  (my/weekly-run-without name)
  (let* ((switch (plist-get (my/module-info name) :switch))
         (before (my/weekly-snapshot))
         (names (my/weekly-names)))
    (unless switch
      (error "%s has no MyPKS-Switch" name))
    (my/modules--load-one name)
    (if (not (member name my/modules-loaded))
        (my/weekly-problem "%s did not load: %S" name (cdr (assoc name my/modules--skipped)))
      (let ((on (my/weekly-snapshot)))
        (funcall switch -1)
        (let ((off (my/weekly-snapshot)))
          (funcall switch 1)
          (let ((again (my/weekly-snapshot)))
            (my/weekly-info "%s on adds %d item(s)" name
                            (length (my/weekly-difference on before)))
            (dolist (item (my/weekly-difference off before))
              (unless (or (not (my/weekly-own-p item))
                          (my/weekly-new-container-p item names)
                          (seq-some (lambda (re) (string-match-p re item))
                                    my/weekly-allowed-leftovers))
                (my/weekly-problem "left behind when off: %s" item)))
            (dolist (item (my/weekly-difference before off))
              (my/weekly-problem "removed when off, though not its own: %s" item))
            (dolist (item (my/weekly-difference again on))
              (my/weekly-problem "on again: more than the first time: %s" item))
            (dolist (item (my/weekly-difference on again))
              (my/weekly-problem "on again: missing since the first time: %s" item))))))))

(defun my/weekly-child (kind name)
  "Run KIND (alone, without, switch) for module NAME; print the outcome.
Called in a child Emacs by test-modules.el.  An error is a PROBLEM too."
  (condition-case err
      (pcase kind
        ("alone" (my/weekly-run-alone name))
        ("without" (my/weekly-run-without name))
        ("switch" (my/weekly-run-switch name))
        (_ (error "No such run: %s" kind)))
    (error (my/weekly-problem "error: %s" (error-message-string err))))
  (princ "DONE\n"))

(provide 'weekly-lib)
;;; lib.el ends here
