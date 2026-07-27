;;; 23-fixed-tabs.el --- Route commands to their own named tab -*- lexical-binding: t; -*-
;;; Commentary:
;; Some activities recur often enough to deserve a permanent home: the
;; dashboard, the journal, the history listings.  This module makes the
;; commands behind them always run in a tab of their own, so that
;; invoking the command is the same gesture as "go to that tab".
;;
;; The mental model this supports is the browser one: a tab is a place
;; where a particular thing lives, and you return to the place rather
;; than searching a list.  Emacs tabs are really named window
;; configurations and any buffer can be shown in any of them, so this
;; correspondence is a convention, not something Emacs enforces.  What
;; the routing does is make the convention hold automatically instead
;; of by hand.
;;
;; Registration is data, not code: add a (COMMAND . "Tab name") pair to
;; `my/fixed-tab-commands' and the routing follows.  Advice is used
;; rather than wrapper commands so that every route into a command is
;; covered at once -- the keybinding, M-x, a transient menu entry, and
;; `emacsclient -n -e' from outside Emacs.
;;
;; Loaded last, because the commands being advised must already exist.

;;; Code:

(defcustom my/fixed-tab-commands
  '((my/denote-journal      . "Journal")
    (my/denote-journal-date . "Journal"))
  "Alist of (COMMAND . TAB-NAME) routed to a fixed tab.
Invoking COMMAND switches to the tab called TAB-NAME first, creating
it to the right of the current tab when absent, and only then runs the
command itself.

Several commands may share a tab name: both journal commands land in
the same Journal tab, which is the point -- the tab is the place where
journalling happens, not one entry point into it.

The dashboard and history commands are deliberately absent: they call
`my/fixed-tab-goto' themselves as part of building their layout, so
routing them here as well would switch tabs twice.  Register a command
here when it has no tab handling of its own.

Changing this variable outside Customize needs
`my/fixed-tab-refresh-advice' to take effect."
  :type '(alist :key-type symbol :value-type string)
  :group 'my/desktop)

(defun my/fixed-tab--install (command tab-name)
  "Make COMMAND run inside the tab called TAB-NAME.
The advice carries a name so that re-evaluating this file replaces the
existing advice instead of stacking another copy on top of it."
  (advice-add command :around
              (lambda (fn &rest args)
                (my/fixed-tab-goto tab-name)
                (apply fn args))
              '((name . my/fixed-tab))))

(defun my/fixed-tab-refresh-advice ()
  "Apply the routing described by `my/fixed-tab-commands'.
Removes any routing installed by an earlier call first, so commands
dropped from the alist stop being routed rather than keeping their old
tab forever."
  (interactive)
  (dolist (entry my/fixed-tab-commands)
    (when (fboundp (car entry))
      (advice-remove (car entry) 'my/fixed-tab)))
  (dolist (entry my/fixed-tab-commands)
    (if (fboundp (car entry))
        (my/fixed-tab--install (car entry) (cdr entry))
      (message "fixed-tabs: no such command, skipped: %s" (car entry)))))

(my/fixed-tab-refresh-advice)

(provide '23-fixed-tabs)
;;; 23-fixed-tabs.el ends here
