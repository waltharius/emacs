;;; 405c-journal-places.el --- Where a journal day was spent -*- lexical-binding: t; -*-

;; MyPKS-Requires: 205-notes
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/journal-places-mode
;; Docs: ~/.emacs.d/function_helper.org::#fn-my-journal-set-place

;;; Commentary:
;; One command, `my/journal-set-place' (C-c n i g), records the place or
;; places a journal day was spent, as a front-matter keyword:
;;
;;     #+identifier: 20261115T000000
;;     #+language:   pl
;;     #+schema:     2
;;     #+wellbeing:  7
;;     #+place:      Kraków; Roma, Włochy
;;
;; WHY A KEYWORD AND NOT A PROPERTY DRAWER
;; ---------------------------------------
;; The same reason as the metrics of 405b-journal-metrics.el, which this
;; module deliberately mirrors: Org parses a file-level property drawer
;; only at the very top of the buffer, above `#+title:', where it fights
;; Denote's front-matter tooling; and a drawer under a headline put a
;; second :PROPERTIES: into files that already had one, which duplicated
;; the metrics block in practice.  A keyword name is unique in the file
;; and has no positional rules.
;;
;; Reading and writing go through the keyword functions of 000-core.el
;; (`my/note-keyword', `my/note-keyword-set', `my/note-keyword-remove'),
;; not through a regexp of this module's own.  Two mechanisms for one
;; format is how the old :well-being: drawer came to be readable by eye
;; and by nothing else.
;;
;; THE VALUE
;; ---------
;; Places are separated by `my/journal-place-separator' (default "; ").
;; The separator is not a comma because a comma belongs inside one place,
;; between a town and a country: "Roma, Włochy".  A place at home carries
;; no country at all, so `my/journal-place-home-country' is stripped when
;; it is typed -- otherwise the same town would appear twice in the
;; completion list, once bare and once with the country.
;;
;; WHERE THE COMPLETION LIST COMES FROM
;; ------------------------------------
;; From the notes, not from a stored list.  The places used so far are
;; derived by scanning the `#+place:' keyword of the journal silo, the
;; way hub membership is computed from note content rather than kept in a
;; field that can drift.  The scan also remembers the newest day each
;; place appears on, which is what orders the list: the place of the last
;; journey comes first, and that order survives a restart and is the same
;; on every machine -- neither of which a minibuffer history would give
;; (`savehist-mode' is not even on here).
;;
;; Only the journal silo is scanned, and the command refuses to run
;; outside a journal note: where a day was spent is a fact about a day.
;;
;; The scan reads the first `my/note-front-matter-limit' characters of
;; each file, as `my/denote--file-title' does, and the result is cached
;; for the session.  A prefix argument rebuilds it; so does writing a
;; place, for the places just written.
;;
;; NUMBERED CHOICES
;; ----------------
;; The first `my/journal-place-quick-count' candidates are shown with a
;; number in front, and typing that number alone chooses them at once --
;; the mechanism of flyspell-correct's completing-read interface, which
;; is what spell correction already does in this configuration: the digit
;; is not bound to a key (it has to stay typable), a hook simply notices
;; that the whole input is an index and leaves the minibuffer.
;;
;; The cost is that a place whose name is nothing but a single digit
;; cannot be typed.  No such town is expected; anything longer, "11
;; Listopada" included, is unaffected, because the input only counts as
;; an index while it is exactly one digit.
;;
;; ATOMICITY
;; ---------
;; Read, prompt, write, in that order: nothing is inserted before every
;; prompt has been answered, so C-g at any point leaves the buffer
;; byte-identical.  RET at the first prompt means "leave it as it is";
;; `my/journal-place-remove-marker' ("-", as in the metrics) removes the
;; keyword.
;;
;; Deleting this file is safe: init.el loads it with NOERROR, the journal
;; template does not depend on it, the menu entry goes through
;; `my/transient-entries', and `#+place:' keywords already written stay
;; in the notes and are ignored by everything else.

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function my/journal-file-date "205-notes" (file))

;; ============================================================
;; OPTIONS
;; ============================================================

(defgroup my/journal-place nil
  "The place a journal day was spent (405c-journal-places.el)."
  :tag "Journal places"
  :group 'mypks-notes)
;; Named for the keyword, not for the module: a group `my/journal-places'
;; would be the name of the function listing them as well, and one symbol
;; cannot be both (lint `duplicates'; 442-obsidian-import.el renamed its
;; group for the same reason).

(defconst my/journal-place-keyword "place"
  "Front-matter keyword carrying the places of a day.
A constant rather than an option: changing it would orphan every value
already written, and the scan would stop finding them.")

(defcustom my/journal-place-separator "; "
  "Separator written between two places of one day.
A comma is deliberately not used: it separates a town from its country
inside a single place."
  :type 'string
  :group 'my/journal-place)

(defcustom my/journal-place-home-country "Polska"
  "Country left out of a place name, or nil to keep every country.
A place with no country is read as being in this one, so the country is
stripped when typed and never written."
  :type '(choice (const :tag "Keep every country" nil) string)
  :group 'my/journal-place)

(defcustom my/journal-place-quick-count 9
  "How many of the most recent places are offered with a number.
At most nine: the index is one digit, so that typing it is one keypress
and cannot be the beginning of a longer number."
  :type 'integer
  :group 'my/journal-place)

(defconst my/journal-place-remove-marker "-"
  "Answer that removes the keyword instead of setting it.
The same marker as the metrics of 405b-journal-metrics.el.")

;; ============================================================
;; THE VALUE
;; ============================================================

(defun my/journal-places--normalize (place)
  "Return PLACE as it is written into a note.
Surrounding and repeated whitespace goes; the home country and the
comma before it go; the spelling, its case and its diacritics stay as
typed -- they are the name of a town, not a key."
  (let ((place (string-trim (replace-regexp-in-string "[ \t]+" " " place))))
    (when (and my/journal-place-home-country
               (string-match (concat "[ \t]*,[ \t]*"
                                     (regexp-quote my/journal-place-home-country)
                                     "[ \t]*\\'")
                             place)
               ;; Only as a suffix after a comma: a town named after the
               ;; country keeps its name.
               (> (match-beginning 0) 0))
      (setq place (substring place 0 (match-beginning 0))))
    (string-trim place)))

(defun my/journal-places--split (value)
  "Return the places in VALUE, a `#+place:' value, as a list of strings."
  (when value
    (seq-remove #'string-empty-p
                (mapcar #'string-trim (split-string value "[ \t]*;[ \t]*" t)))))

(defun my/journal-places--join (places)
  "Return PLACES as one `#+place:' value."
  (string-join places my/journal-place-separator))

(defun my/journal-places--current ()
  "Return the places recorded in the current buffer, as a list."
  (my/journal-places--split (my/note-keyword my/journal-place-keyword)))

;; ============================================================
;; THE LIST OF PLACES USED SO FAR
;; ============================================================

(defvar my/journal-places--cache nil
  "Alist of (PLACE . DAY), newest day first.
DAY is the journal day the place was last recorded on, as YYYY-MM-DD,
or nil for a file whose day cannot be read from its name.")

(defvar my/journal-places--scanned nil
  "Non-nil once the journal silo has been scanned in this session.
A flag of its own rather than a non-empty cache: a silo with no place
recorded yet scans to an empty list, and the two states have to be told
apart -- otherwise the first place written would not reach the list
until something else rebuilt it.")

(defun my/journal-places--file-places (file)
  "Return the places recorded in FILE, reading only its front matter."
  (with-temp-buffer
    (ignore-errors
      (insert-file-contents file nil 0 my/note-front-matter-limit))
    (my/journal-places--current)))

(defun my/journal-places--day-newer-p (a b)
  "Non-nil when day A is newer than day B.  A nil day is the oldest."
  (cond ((null b) (and a t))
        ((null a) nil)
        (t (string> a b))))

(defun my/journal-places--scan ()
  "Return an alist of (PLACE . DAY) from the journal silo, newest first.
DAY is the newest journal day the place appears on, so the order is the
order of last visit.  Equal days keep an alphabetical order, which makes
the list stable from one call to the next."
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (file (my/notes-files my-notes-journal "\\.org\\'"))
      (let ((day (my/journal-file-date file)))
        (dolist (place (my/journal-places--file-places file))
          (let ((known (gethash place seen 'none)))
            (when (or (eq known 'none)
                      (my/journal-places--day-newer-p day known))
              (puthash place day seen))))))
    (let (pairs)
      (maphash (lambda (place day) (push (cons place day) pairs)) seen)
      (sort pairs (lambda (a b)
                    (if (equal (cdr a) (cdr b))
                        (string< (car a) (car b))
                      (my/journal-places--day-newer-p (cdr a) (cdr b))))))))

(defun my/journal-places (&optional refresh)
  "Return the places used so far, most recently visited first.
Scans the journal silo once per session; with REFRESH, scans again."
  (when (or refresh (not my/journal-places--scanned))
    (setq my/journal-places--cache (my/journal-places--scan))
    (setq my/journal-places--scanned t))
  (mapcar #'car my/journal-places--cache))

(defun my/journal-places--record (places day)
  "Note in the cache that PLACES were recorded on DAY.
Does nothing before the first scan: there is no list yet to add to, and
the scan will read the file just written anyway."
  (when my/journal-places--scanned
    (dolist (place places)
      (let ((known (assoc place my/journal-places--cache)))
        (if (and known (my/journal-places--day-newer-p day (cdr known)))
            (setcdr known day)
          (unless known
            (push (cons place day) my/journal-places--cache)))))
    (setq my/journal-places--cache
          (sort my/journal-places--cache
                (lambda (a b)
                  (if (equal (cdr a) (cdr b))
                      (string< (car a) (car b))
                    (my/journal-places--day-newer-p (cdr a) (cdr b))))))))

;; ============================================================
;; PROMPTING
;; ============================================================

(defun my/journal-places--displays (candidates)
  "Return an alist of (DISPLAY . PLACE) for CANDIDATES.
The first `my/journal-place-quick-count' places are shown behind their
number; the rest are shown as they are and reached by typing."
  (let ((index 0))
    (mapcar (lambda (place)
              (setq index (1+ index))
              (if (<= index (min 9 my/journal-place-quick-count))
                  (cons (format "%d %s" index place) place)
                (cons place place)))
            candidates)))

(defun my/journal-places--quick (input displays)
  "Return the place INPUT selects by its number, or nil.
Only a whole input of one digit counts, so that a name can still be
typed."
  (when (string-match-p "\\`[1-9]\\'" input)
    (let* ((index (string-to-number input))
           (entry (nth (1- index) displays)))
      ;; Only an entry that is actually shown behind that number: past
      ;; `my/journal-place-quick-count' the candidates carry no index,
      ;; and a digit then means a digit.
      (when (and entry (string-prefix-p (format "%d " index) (car entry)))
        (cdr entry)))))

(defun my/journal-places--table (displays)
  "Return a completion table over DISPLAYS keeping their order.
Without the sort functions the completion framework would re-sort the
candidates and the order of last visit -- the point of the list -- would
be lost."
  (let ((keys (mapcar #'car displays)))
    (lambda (string pred action)
      (if (eq action 'metadata)
          '(metadata (category . my/journal-place)
                     (display-sort-function . identity)
                     (cycle-sort-function . identity))
        (complete-with-action action keys string pred)))))

(defun my/journal-places--read (prompt candidates)
  "Read one place, offering CANDIDATES.  Return a string, empty for none.
A number chosen from the list leaves the minibuffer at once; anything
else is read as typed, so a place used for the first time needs no
ceremony."
  (let* ((displays (my/journal-places--displays candidates))
         (quick nil)
         (answer (minibuffer-with-setup-hook
                     (lambda ()
                       (add-hook 'post-command-hook
                                 (lambda ()
                                   (let ((place (my/journal-places--quick
                                                 (minibuffer-contents-no-properties)
                                                 displays)))
                                     (when place
                                       (setq quick place)
                                       (exit-minibuffer))))
                                 nil t))
                   (completing-read prompt (my/journal-places--table displays)
                                    nil nil))))
    (or quick (cdr (assoc answer displays)) (string-trim answer))))

(defun my/journal-places--prompt (collected current)
  "Return the prompt for the next place.
COLLECTED are the places answered so far, CURRENT those already in the
note."
  (cond
   (collected (format "Kolejne miejsce [%s] (RET = koniec): "
                      (my/journal-places--join collected)))
   (current (format "Miejsce [%s] (RET = bez zmian, %s = usuń): "
                    (my/journal-places--join current)
                    my/journal-place-remove-marker))
   (t (format "Miejsce (RET = pomiń, %s = usuń): "
              my/journal-place-remove-marker))))

(defun my/journal-places--ask (current)
  "Ask for the places of the day.  Nothing is written here.
Returns a list of places, the symbol `remove', or nil for no change.
CURRENT are the places already recorded."
  (let ((candidates (my/journal-places))
        (collected nil)
        (result nil)
        (done nil))
    (while (not done)
      (let ((answer (my/journal-places--read
                     (my/journal-places--prompt collected current)
                     candidates)))
        (cond
         ((string-empty-p answer)
          (setq result (and collected (nreverse collected)))
          (setq done t))
         ((string= answer my/journal-place-remove-marker)
          (if collected
              (message "%s kończy pytanie tylko jako pierwsza odpowiedź"
                       my/journal-place-remove-marker)
            (setq result 'remove)
            (setq done t)))
         (t
          (let ((place (my/journal-places--normalize answer)))
            (cond
             ((string-empty-p place) nil)
             ((seq-find (lambda (other) (string-equal-ignore-case other place))
                        collected)
              (message "%s już na liście" place))
             (t (push place collected))))))))
    result))

;; ============================================================
;; COMMAND
;; ============================================================

;;;###autoload
(defun my/journal-set-place (&optional refresh)
  "Record the places the journal day in the current buffer was spent in.

Asks for one place after another, with the places used so far offered in
the order of last visit and the first few reachable by their number.
RET on an empty first answer changes nothing; `-' removes the keyword.
Nothing is written before the last prompt is answered.

With a prefix argument REFRESH, the list of places is scanned again
before the first prompt -- for notes changed outside this Emacs."
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (unless (and buffer-file-name (my/journal-file-date buffer-file-name))
    (user-error "Not a journal note: a place belongs to a day"))
  (when refresh
    (my/journal-places t))
  (let* ((day (my/journal-file-date buffer-file-name))
         (current (my/journal-places--current))
         (answer (my/journal-places--ask current)))
    ;; --- write phase ---
    (cond
     ((null answer)
      (message "Miejsce bez zmian"))
     ((eq answer 'remove)
      (if (my/note-keyword-remove my/journal-place-keyword)
          (progn (save-buffer) (message "Miejsce usunięte"))
        (message "Miejsce nie było zapisane")))
     (t
      (my/note-keyword-set my/journal-place-keyword
                           (my/journal-places--join answer)
                           my/note-front-matter-column)
      (save-buffer)
      (my/journal-places--record answer day)
      (message "Miejsce: %s" (my/journal-places--join answer))))))

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/journal-places-mode' is this module's switch (module contract,
;; rule 12): on, the Place entry of the Insert menu (C-c n i g); off,
;; gone.  The command stays defined for M-x.  Customize saves the
;; position in this machine's settings (M-x customize-option RET
;; my/journal-places-mode).

(defconst my/journal-places--menu-entries
  '((append my/notes-insert-menu "w" ("g" "Place of the day" my/journal-set-place)))
  "Menu entries of this module, for `my/transient-entries'.")

(define-minor-mode my/journal-places-mode
  "Journal places as a module, switched on and off.
On: Place of the day in the Insert menu (C-c n i g).  Off: it is gone,
and the command remains for M-x."
  :global t
  :init-value t
  :group 'my/journal-place
  (with-eval-after-load '212-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/journal-places-mode my/journal-places--menu-entries))))

(my/journal-places-mode (if my/journal-places-mode 1 -1))

(provide '405c-journal-places)
;;; 405c-journal-places.el ends here
