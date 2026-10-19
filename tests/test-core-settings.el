;;; test-core-settings.el --- ERT tests for the settings folder and host of 00-core -*- lexical-binding: t; -*-
;;; Commentary:
;; Which settings folder and which host folder 00-core.el chooses, and
;; what it refuses: precedence of MYPKS_DIR / MYPKS_HOST over
;; mypks-local.eld over the defaults, host names that would leave
;; hosts/, and a mypks-local.eld that cannot be read.
;;
;; The choice is made once, while 00-core.el loads (`my/settings-directory'
;; and `my/host-name' are constants), so every case starts a fresh
;; `emacs -Q --batch' with its own HOME and environment and reads the
;; result back.  00-core.el needs no package beyond what Emacs 29 ships.
;; From the repository's folder:
;;
;;   emacs -Q --batch -l tests/test-core-settings.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; Nothing outside a temporary folder is read or written.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defconst my/core-test--repo
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "The repository's folder.")

(defun my/core-test--run (env &optional local-text extra)
  "Load 00-core.el in a fresh Emacs with ENV; return what it chose.
ENV is a list of \"NAME=value\" strings added to the environment.
LOCAL-TEXT, when non-nil, is written to mypks-local.eld first.  The
result is a plist: :dir (the settings folder, relative to the home),
:host, :reports (kind and title of each report), :put (the error
message of a write to mypks-local.eld, or nil) and :extra, the value
of EXTRA, a form given as a string, evaluated after loading."
  (let* ((home (make-temp-file "mypks-core-" t))
         (emacs-dir (expand-file-name ".emacs.d/" home))
         (out (expand-file-name "result.eld" home))
         (process-environment
          (append (list (concat "HOME=" home)) env
                  (seq-remove (lambda (e) (string-match-p "\\`\\(HOME\\|MYPKS_DIR\\|MYPKS_HOST\\)=" e))
                              process-environment))))
    (unwind-protect
        (progn
          (make-directory emacs-dir t)
          (when local-text
            (with-temp-file (expand-file-name "mypks-local.eld" emacs-dir)
              (insert local-text)))
          (call-process
           (expand-file-name invocation-name invocation-directory) nil nil nil
           "-Q" "--batch"
           ;; A test installs nothing (no-littering, 00-core.el): without
           ;; this each start tried the network, seconds per case.
           "--eval" "(setq use-package-ensure-function 'ignore)"
           "--eval" (format "(setq user-emacs-directory %S)" emacs-dir)
           ;; Reports are collected, not shown: in batch they would only print.
           "--eval" "(setq my/test-reports nil)"
           "--eval" "(advice-add 'my/notes-report :override (lambda (kind title &rest _) (push (list kind title) my/test-reports)))"
           "--eval" (format "(condition-case nil (load %S nil t) (error nil))"
                            (expand-file-name "modules/00-core.el" my/core-test--repo))
           "--eval" (format "(with-temp-file %S (prin1 (list :dir (file-relative-name my/settings-directory %S) :host my/host-name :reports (reverse my/test-reports) :put (condition-case err (progn (my/local--put :test t) nil) (error (error-message-string err))) :extra %s) (current-buffer)))"
                            out home (or extra "nil")))
          (when (file-readable-p out)
            (with-temp-buffer
              (insert-file-contents out)
              (read (current-buffer)))))
      (delete-directory home t))))

(defun my/core-test--titles (result)
  "Return the report titles in RESULT, as one string."
  (mapconcat (lambda (r) (format "%s %s" (car r) (cadr r)))
             (plist-get result :reports) " | "))

;; ============================================================
;; PRECEDENCE
;; ============================================================

(ert-deftest my/core-test-defaults ()
  "Nothing set: ~/.config/mypks/ and the machine's own name."
  (let ((r (my/core-test--run nil)))
    (should (equal (plist-get r :dir) ".config/mypks/"))
    (should (equal (plist-get r :host)
                   (downcase (car (split-string (system-name) "\\.")))))))

(ert-deftest my/core-test-local-file-wins-over-default ()
  "mypks-local.eld names the folder and the host."
  (let ((r (my/core-test--run nil "(:directory \"~/s1/\" :host \"other\")")))
    (should (equal (plist-get r :dir) "s1/"))
    (should (equal (plist-get r :host) "other"))))

(ert-deftest my/core-test-environment-wins ()
  "MYPKS_DIR and MYPKS_HOST win over mypks-local.eld."
  (let ((r (my/core-test--run '("MYPKS_DIR=~/s2/" "MYPKS_HOST=envhost")
                              "(:directory \"~/s1/\" :host \"other\")")))
    (should (equal (plist-get r :dir) "s2/"))
    (should (equal (plist-get r :host) "envhost"))))

;; ============================================================
;; HOST NAMES THAT WOULD LEAVE hosts/
;; ============================================================

(ert-deftest my/core-test-host-name-validity ()
  "Only one plain folder name is a host name."
  (let* ((good '("laptop" "desk" "my-pc_2" "pc.local"))
         (bad '("" "." ".." "../x" "/etc" "a/b" "a\\b" "~x" "~" "a\nb"))
         (r (my/core-test--run
             nil nil
             (format "(mapcar (lambda (n) (and (my/host--valid-name-p n) t)) '%S)"
                     (append good bad)))))
    (should (equal (plist-get r :extra)
                   (append (make-list (length good) t)
                           (make-list (length bad) nil))))))

(ert-deftest my/core-test-traversal-from-environment-refused ()
  "MYPKS_HOST=../x is refused, reported, and the own name used."
  (let ((r (my/core-test--run '("MYPKS_HOST=../escape"))))
    (should-not (equal (plist-get r :host) "../escape"))
    (should (string-match-p "refused Host name \"\\.\\./escape\" not used"
                            (my/core-test--titles r)))))

(ert-deftest my/core-test-absolute-host-from-local-file-refused ()
  "An absolute :host is refused; the next source is used."
  (let ((r (my/core-test--run nil "(:host \"/tmp/elsewhere\")")))
    (should-not (equal (plist-get r :host) "/tmp/elsewhere"))
    (should (string-match-p "refused Host name" (my/core-test--titles r)))))

;; ============================================================
;; A DAMAGED mypks-local.eld
;; ============================================================

(ert-deftest my/core-test-damaged-local-file-reported ()
  "A cut-short file is reported, the defaults used, and not overwritten."
  (let ((r (my/core-test--run nil "(:directory \"~/s1/\" :ho")))
    (should (equal (plist-get r :dir) ".config/mypks/"))
    (should (string-match-p "failed .*mypks-local\\.eld cannot be read"
                            (my/core-test--titles r)))
    (should (string-match-p "cannot be read" (or (plist-get r :put) "")))))

(ert-deftest my/core-test-not-a-list-reported ()
  "A file holding something other than a plist is damaged too."
  (let ((r (my/core-test--run nil "\"just a string\"")))
    (should (equal (plist-get r :dir) ".config/mypks/"))
    (should (string-match-p "cannot be read" (my/core-test--titles r)))))

(ert-deftest my/core-test-clean-local-file-writable ()
  "A readable file can be written."
  (let ((r (my/core-test--run nil "(:host \"other\")")))
    (should (null (plist-get r :put)))))

(provide 'test-core-settings)
;;; test-core-settings.el ends here
