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

;; ============================================================
;; DETACHING TO A SEPARATE FRAME
;; ============================================================
;; The counterpart to fixed tabs.  A tab is a place you return to, and
;; it is exclusive: while you look at it, you are not looking at
;; anything else.  A frame is a separate operating-system window, so it
;; can sit on another monitor and be read *alongside* whatever you are
;; working on.
;;
;; That makes them suit different things.  Journal and Dashboard are
;; destinations, so they get tabs.  A keybinding cheat sheet or a list
;; of old entries you are skimming through is something you want beside
;; the work, so it wants a frame.
;;
;; Emacs cannot place a frame on a particular monitor by itself -- that
;; is the window manager's job.  These commands create the frame; where
;; it lands is up to the WM, and moving it once is usually enough since
;; most window managers remember placement per window.

(defcustom my/detached-frame-parameters
  '((width . 90)
    (height . 45))
  "Frame parameters for frames made by `my/detach-buffer-to-frame'.
Deliberately small: these frames are meant to be read beside the main
frame, not worked in full screen.  Monitor placement is not settable
here; that is up to the window manager."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'my/desktop)

(defun my/detach-buffer-to-frame ()
  "Show the current buffer in its own frame and remove it from this one.

The new frame is selected, so the buffer can be read or edited
immediately; move it to another monitor once and most window managers
will remember the position.

The window that displayed the buffer here is closed when it is not the
only window in the tab, which is what makes this a move rather than a
duplication.  A sole window is left alone, since deleting it would
delete the tab along with it."
  (interactive)
  (let ((buffer (current-buffer))
        (window (selected-window)))
    (make-frame (append my/detached-frame-parameters
                        (list (cons 'name (buffer-name buffer)))))
    (select-frame-set-input-focus (selected-frame))
    (switch-to-buffer buffer)
    (when (window-live-p window)
      (with-selected-window window
        (unless (one-window-p)
          (delete-window window))))))

(defun my/detach-tab-to-frame ()
  "Move the current tab, with its whole window layout, into a new frame.

Uses `tab-bar-detach-tab', which has existed since Emacs 28.  Unlike
`my/detach-buffer-to-frame' this preserves splits, so it is the right
choice for a tab such as History whose value lies in its two-pane
layout.

Refuses when the tab is the only one, because detaching it would leave
the frame with nothing in it."
  (interactive)
  (cond
   ((not (fboundp 'tab-bar-detach-tab))
    (user-error "This Emacs has no `tab-bar-detach-tab' (needs Emacs 28+)"))
   ((< (length (tab-bar-tabs)) 2)
    (user-error "Refusing to detach the only tab in this frame"))
   (t
    (call-interactively #'tab-bar-detach-tab))))

(provide '23-fixed-tabs)
;;; 23-fixed-tabs.el ends here
