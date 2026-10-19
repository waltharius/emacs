;;; 14-typing-analytics.el --- Track typing patterns for ergonomic analysis -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/typing-analytics-mode
;; MyPKS-Writes: var/keys, var/keyfreq.el
;; Docs: ~/.emacs.d/function_helper.org::#typing-analytics

;;; Commentary:
;; This module tracks:
;; 1. Command frequency (keyfreq) - which Emacs commands you use most
;; 2. Character-level typing patterns - actual keystrokes, speed, and hand/finger usage
;;
;; All data is stored locally:
;; - <settings folder>/hosts/<host>/var/keyfreq.el (command statistics)
;; - <settings folder>/hosts/<host>/var/keys (character-level data)
;;
;; Purpose: Gather data for ergonomic keyboard selection

;;; Code:

;; ============================================================
;; KEYFREQ: Track command frequency
;; ============================================================

;; Ensure json library is loaded (fixes compilation warning)
(require 'json)

(defgroup my/typing-analytics nil
  "Command frequency and keystroke logging (14-typing-analytics.el)."
  :tag "Typing analytics"
  :group 'mypks-tools)

;; Installed here; switched on and off with the module
;; (`my/typing-analytics-mode', below).  Command names only, no text.
(use-package keyfreq
  :ensure t
  :defer t
  :commands (keyfreq-mode keyfreq-autosave-mode keyfreq-show))

;; C-c y k shows the statistics.  Moved off the "C-c a" prefix 2026-08.
;; "C-c a" is the agenda key in every piece of Org documentation there
;; is, and holding it for four commands opened a few times a year, at
;; the cost of the one opened every morning, was the wrong way round.

;; ============================================================
;; CHARACTER-LEVEL TYPING ANALYTICS
;; ============================================================
;; Based on Pavel Panchekha's typing analytics system
;; Tracks: character frequency, digraphs, timing, hand/finger patterns
;;
;; OFF BY DEFAULT.  The log is every character typed, with its time, in
;; plain text -- a copy of the writing itself outside the notes folder,
;; where sync tools and backups may pick it up.  It is switched on for
;; a collection period on purpose (`my/keylog-enabled'), and never
;; records a buffer visiting a note of a private silo (the journal).
;;
;; Renamed from `keylog-*' to `my/keylog-*' in 2026-10, with obsolete
;; aliases for the old names: unprefixed names in a configuration risk
;; colliding with a package of the same name.

;; Aliases first: an alias declared after its referent is a warning,
;; and a saved old name must reach the new variable.
(define-obsolete-variable-alias 'keylog-file 'my/keylog-file "2026-10")
(define-obsolete-variable-alias 'keylog-buffer-size 'my/keylog-buffer-size "2026-10")
(define-obsolete-variable-alias 'keylog-buffer 'my/keylog-buffer "2026-10")
(define-obsolete-variable-alias 'keylog-last-save-time 'my/keylog-last-save-time "2026-10")
(define-obsolete-variable-alias 'keylog-autosave-interval 'my/keylog-autosave-interval "2026-10")

(defvar my/keylog-file (my/var-file "keys")
  "File to store raw keystroke data with timestamps.
In var/ of this machine (00-core.el): personal, per machine, never in
git.  Until 2026-10-19 it was ~/.emacs.d/keys; 00-core.el moves it.")

;; WHEN THE LOG REACHES THE DISK.  Keystrokes are collected in memory
;; and appended to the file in batches, whichever comes first:
;;   - `my/keylog-buffer-size' keystrokes collected;
;;   - `my/keylog-autosave-interval' seconds since the last write, checked
;;     at each keystroke, so continuous typing is written too;
;;   - `my/keylog-idle-save-seconds' of idleness: whatever is collected;
;;   - turning the log off, and quitting Emacs.
;; At most that much is lost if Emacs crashes.  Until 2026-10 it was 1000
;; keystrokes, or five minutes checked only after a minute of idleness,
;; so continuous typing reached the disk once per 1000 characters.

(defcustom my/keylog-buffer-size 200
  "Keystrokes collected in memory before they are appended to the log."
  :type 'integer
  :tag "Write after this many keystrokes"
  :group 'my/typing-analytics)

(defcustom my/keylog-autosave-interval 60
  "Seconds after which collected keystrokes are written while typing."
  :type 'integer
  :tag "Write at least every N seconds"
  :group 'my/typing-analytics)

(defcustom my/keylog-idle-save-seconds 30
  "Seconds of idleness after which collected keystrokes are written.
Takes effect at the next `my/keylog-enable', or at once when the log
is on."
  :type 'integer
  :tag "Write after N seconds idle"
  :set (my/settings-apply-on-set #'my/keylog--restart-timer)
  :group 'my/typing-analytics)

(defvar my/keylog-buffer nil
  "Buffer for keystroke data before writing to file.")

(defvar my/keylog--count 0
  "Number of keystrokes in `my/keylog-buffer'.")

(defvar my/keylog-last-save-time (current-time)
  "Last time the keylog was saved to disk.")

(defvar my/keylog--timer nil
  "Idle timer saving the keylog buffer; one at most.")

(defun my/keylog--private-buffer-p ()
  "Non-nil when the current buffer visits a note of a private silo."
  (and buffer-file-name
       (fboundp 'my/silo-of)
       (when-let* ((key (my/silo-of buffer-file-name t)))
         (my/silo-get key :private))))

(defun my/keylog-record-keystroke ()
  "Record a single keystroke with microsecond timestamp.
On `post-self-insert-hook', so every self-inserting command counts --
`org-self-insert-command' in notes as much as `self-insert-command'
elsewhere.  Not in the minibuffer, and not in a private silo."
  (when (and (not (minibufferp))
             (characterp last-command-event)
             (not (my/keylog--private-buffer-p)))
    (push (cons (float-time) (char-to-string last-command-event)) my/keylog-buffer)
    (setq my/keylog--count (1+ my/keylog--count))
    (when (or (>= my/keylog--count my/keylog-buffer-size)
              (> (float-time (time-since my/keylog-last-save-time))
                 my/keylog-autosave-interval))
      (my/keylog-save-buffer))))

(defun my/keylog-save-buffer ()
  "Write buffered keystrokes to file."
  (when my/keylog-buffer
    (with-temp-buffer
      (dolist (entry (reverse my/keylog-buffer))
        (insert (format "%.6f\t%s\n" (car entry) (cdr entry))))
      (write-region (point-min) (point-max) my/keylog-file t 'silent))
    (setq my/keylog-buffer nil
          my/keylog--count 0
          my/keylog-last-save-time (current-time))))

(defun my/keylog-autosave ()
  "Write whatever is collected; run after `my/keylog-idle-save-seconds' idle."
  (my/keylog-save-buffer))

(defun my/keylog--restart-timer ()
  "Restart the idle timer with the current delay, when the log is on."
  (when (timerp my/keylog--timer)
    (cancel-timer my/keylog--timer)
    (setq my/keylog--timer
          (run-with-idle-timer my/keylog-idle-save-seconds t #'my/keylog-autosave))))

(defun my/keylog-enable ()
  "Start keystroke logging for this session.
Idempotent: the idle timer is started once, not once per call.  To log
in every session, turn on `my/keylog-enabled' in C-c n ,."
  (interactive)
  (add-hook 'post-self-insert-hook #'my/keylog-record-keystroke)
  (unless (timerp my/keylog--timer)
    (setq my/keylog--timer
          (run-with-idle-timer my/keylog-idle-save-seconds t #'my/keylog-autosave)))
  (add-hook 'kill-emacs-hook #'my/keylog-save-buffer)
  (when (called-interactively-p 'interactive)
    (message "Keystroke logging ON for this session (%s); private silos are skipped"
             (abbreviate-file-name my/keylog-file))))

(defun my/keylog-disable ()
  "Stop keystroke logging, save what is buffered, stop the timer."
  (interactive)
  (remove-hook 'post-self-insert-hook #'my/keylog-record-keystroke)
  (when (timerp my/keylog--timer)
    (cancel-timer my/keylog--timer))
  (setq my/keylog--timer nil)
  (my/keylog-save-buffer)
  (remove-hook 'kill-emacs-hook #'my/keylog-save-buffer)
  (when (called-interactively-p 'interactive)
    (message "Keystroke logging OFF")))

(defun my/keylog-status ()
  "Show current keylog statistics."
  (interactive)
  (message "Keylog %s: %d keystrokes buffered, file size: %s"
           (if (memq #'my/keylog-record-keystroke post-self-insert-hook) "ON" "OFF")
           (length my/keylog-buffer)
           (if (file-exists-p my/keylog-file)
               (file-size-human-readable (file-attribute-size (file-attributes my/keylog-file)))
             "0 bytes")))

(define-obsolete-function-alias 'keylog-record-keystroke #'my/keylog-record-keystroke "2026-10")
(define-obsolete-function-alias 'keylog-save-buffer #'my/keylog-save-buffer "2026-10")
(define-obsolete-function-alias 'keylog-autosave #'my/keylog-autosave "2026-10")
(define-obsolete-function-alias 'keylog-enable #'my/keylog-enable "2026-10")
(define-obsolete-function-alias 'keylog-disable #'my/keylog-disable "2026-10")
(define-obsolete-function-alias 'keylog-status #'my/keylog-status "2026-10")

(defcustom my/keylog-enabled nil
  "Non-nil logs every typed character with its time to `my/keylog-file'.
Off by default: the log is a plain-text copy of what is written.
Buffers visiting notes of a private silo are never logged.  Takes
effect at once.  `C-c y T' and `C-c y t' switch it for one session."
  :type 'boolean
  :tag "Log keystrokes (typing analytics)"
  :set (my/settings-apply-on-set #'my/keylog--apply)
  :group 'my/typing-analytics)

(defvar my/typing-analytics-mode)

(defun my/keylog--apply ()
  "Start or stop logging as `my/keylog-enabled' and the module's switch say.
Logging runs only while both are on."
  (if (and my/keylog-enabled (bound-and-true-p my/typing-analytics-mode))
      (my/keylog-enable)
    (my/keylog-disable)))

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/typing-analytics-mode' is this module's switch (module contract,
;; rule 12): on, command frequency is counted (keyfreq), the keystroke
;; log runs if `my/keylog-enabled' says so, and the keys C-c y k/s/t/T
;; work; off, nothing is counted or logged -- what was collected is
;; written to disk first -- and the keys are gone.  The commands stay
;; defined for M-x.  Customize saves the position in this machine's
;; settings (M-x customize-option RET my/typing-analytics-mode).

(defconst my/typing-analytics--keys
  '(("C-c y k" . keyfreq-show)
    ("C-c y s" . my/keylog-status)
    ("C-c y t" . my/keylog-disable)   ; off for this session
    ("C-c y T" . my/keylog-enable))   ; on for this session
  "Global keys of this module, for `my/module-keys'.")

(declare-function keyfreq-table-save "keyfreq" (table &optional mustsave))
(defvar keyfreq-table)

(define-minor-mode my/typing-analytics-mode
  "Typing analytics as a module: command counts, the keystroke log, C-c y.
Turned off, nothing is counted or logged (collected data is written
first) and the keys are gone; the commands remain for M-x.  Customize
saves the position in this machine's settings."
  :global t
  :init-value t
  :group 'my/typing-analytics
  (if my/typing-analytics-mode
      (when (require 'keyfreq nil t)
        (keyfreq-mode 1)
        (keyfreq-autosave-mode 1))
    (when (bound-and-true-p keyfreq-mode)
      ;; Written now: keyfreq saves only from its timer and at exit.
      (when (and (fboundp 'keyfreq-table-save) (boundp 'keyfreq-table))
        (keyfreq-table-save keyfreq-table t))
      (keyfreq-autosave-mode -1)
      (keyfreq-mode -1)))
  (my/keylog--apply)
  (my/module-keys my/typing-analytics-mode my/typing-analytics--keys))

(my/typing-analytics-mode (if my/typing-analytics-mode 1 -1))

;; ============================================================
;; USAGE INSTRUCTIONS
;; ============================================================
;;
;; Active keybindings:
;; - C-c y k : View command frequency statistics (keyfreq-show)
;; - C-c y s : Show current keylog status
;; - C-c y t : Stop character tracking for this session
;; - C-c y T : Start character tracking for this session
;;
;; Data locations:
;; - <settings folder>/hosts/<host>/var/keyfreq.el - Command frequency data
;; - <settings folder>/hosts/<host>/var/keys - Raw keystroke data with timestamps
;;
;; Recommended collection period: 2-4 weeks for representative data
;;
;; Privacy: All data stays on this machine.  var/ is in the settings
;; folder's .gitignore (00-core.el).

(provide '14-typing-analytics)
;;; 14-typing-analytics.el ends here
