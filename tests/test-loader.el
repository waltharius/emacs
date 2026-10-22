;;; test-loader.el --- ERT tests for the module loader of 00-core -*- lexical-binding: t; -*-

;; Tests: 00-core

;;; Commentary:
;; `my/modules-load' and `my/modules-toggle' (00-core.el) on a set of
;; small stand-in modules in a temporary folder, each a few lines with
;; the headers the loader reads:
;;
;;   01-a  core
;;   02-b  needs 03-c, which loads after it -- must load all the same
;;   03-c  plain optional
;;   04-d  turned off on this machine
;;   05-e  needs 04-d: left out
;;   06-f  needs 05-e: left out in turn
;;   07-g  signals an error while loading: start-up goes on
;;   08-h  has a switch, my/h-mode
;;   09-i  needs a module that is not in the list at all
;;
;; 00-core.el reads the modules folder once, at load, from
;; `user-emacs-directory', so the checks run in a fresh `emacs -Q
;; --batch' with its own HOME; each prints PASS or FAIL.  From the
;; repository's folder:
;;
;;   emacs -Q --batch -l tests/test-loader.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)

(defconst my/loader-test--repo
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "The repository's folder.")

(defconst my/loader-test--modules
  '(("01-a" "no" "" nil "")
    ("02-b" "yes" "03-c" nil "")
    ("03-c" "yes" "" nil "")
    ("04-d" "yes" "" nil "")
    ("05-e" "yes" "04-d" nil "")
    ("06-f" "yes" "05-e" nil "")
    ("07-g" "yes" "" nil "(error \"boom in g\")")
    ("08-h" "yes" "" "my/h-mode"
     "(define-minor-mode my/h-mode \"h\" :global t :init-value t)\n(my/h-mode (if my/h-mode 1 -1))")
    ("09-i" "yes" "99-missing" nil ""))
  "(NAME OPTIONAL REQUIRES SWITCH BODY) of each stand-in module.")

(defconst my/loader-test--checks
  "(defvar test-loaded nil)
(setq my/modules-off '(\"04-d\"))
(my/modules-load '(\"01-a\" \"02-b\" \"03-c\" \"04-d\" \"05-e\" \"06-f\" \"07-g\" \"08-h\" \"09-i\"))
(check \"loaded in init.el order\" (equal my/modules-loaded '(\"00-core\" \"01-a\" \"02-b\" \"03-c\" \"08-h\")))
(check \"02-b loaded although its requirement loads later\" (member \"02-b\" test-loaded))
(check \"reasons\" (equal (mapcar (lambda (e) (cons (car e) (if (consp (cdr e)) (cadr e) (cdr e)))) my/modules--skipped)
                        '((\"04-d\" . off) (\"05-e\" . needs) (\"06-f\" . needs) (\"07-g\" . failed) (\"09-i\" . needs))))
(check \"failed message kept\" (equal (cddr (assoc \"07-g\" my/modules--skipped)) \"boom in g\"))
(let ((warned nil) (said nil))
  (cl-letf (((symbol-function 'display-warning) (lambda (_ m &rest _) (setq warned m)))
            ((symbol-function 'message) (lambda (f &rest a) (setq said (apply #'format f a)))))
    (my/modules--warn))
  (check \"start-up line counts loaded, off, not loaded\" (equal said \"Modules: 5 loaded, 1 off on this machine, 4 not loaded -- C-c n , m lists them\"))
  (check \"warning lists failed and needs, not off\" (and (string-match-p \"07-g: FAILED.*boom\" warned) (string-match-p \"05-e: not loaded, needs 04-d\" warned) (not (string-match-p \"04-d: turned off\" warned)))))
(check \"states\" (equal (mapcar #'my/modules--state '(\"01-a\" \"04-d\" \"05-e\" \"07-g\" \"08-h\")) '(\"core\" \"off\" \"not loaded: needs a module that is off\" \"FAILED at start-up\" \"on\")))
(check \"dependants of 04-d\" (equal (my/modules--dependants \"04-d\" my/modules-order) '(\"05-e\" \"06-f\")))
;; Turning off 08-h: switch off now, saved off.
(cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)) ((symbol-function 'customize-save-variable) (lambda (s v &rest _) (set s v))))
  (my/modules-toggle \"08-h\")
  (check \"08-h off: in list, switch off\" (and (member \"08-h\" my/modules-off) (not my/h-mode)))
  (my/modules-toggle \"08-h\")
  (check \"08-h on: out of list, switch on\" (and (not (member \"08-h\" my/modules-off)) my/h-mode))
  ;; Turning on 06-f: brings 04-d along, loads 04-d, 05-e, 06-f now.
  (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
    (my/modules-toggle \"06-f\"))
  (check \"06-f on: requirements turned on and loaded in order\" (and (null my/modules-off) (equal (last my/modules-loaded 3) '(\"04-d\" \"05-e\" \"06-f\"))))
  (check \"no stale skips for them\" (not (assoc \"05-e\" my/modules--skipped)))
  ;; Turning off 04-d asks about its dependants and turns all off.
  (my/modules-toggle \"04-d\")
  (check \"04-d off with dependants\" (equal (sort (copy-sequence my/modules-off) #'string<) '(\"04-d\" \"05-e\" \"06-f\")))
  (check \"core refused\" (condition-case nil (progn (my/modules-toggle \"01-a\") nil) (user-error t))))
"
  "The checks, run in the child Emacs after 00-core.el.")

(defun my/loader-test--run ()
  "Write the stand-in modules, run the checks in a child Emacs; return its output."
  (let* ((root (make-temp-file "mypks-loader-" t))
         (emacs-dir (expand-file-name "ed/" root))
         (modules (expand-file-name "modules/" emacs-dir))
         (script (expand-file-name "checks.el" root))
         ;; The child starts in the temporary folder.  Emacs keeps the
         ;; current folder as "~/.emacs.d/" when it is under HOME, and
         ;; with HOME changed below that "~" would mean the temporary
         ;; HOME, where no .emacs.d exists: "Setting current directory".
         (default-directory (file-name-as-directory root))
         (process-environment
          (append (list (concat "HOME=" root)
                        (concat "MYPKS_DIR=" (expand-file-name "settings" root)))
                  process-environment)))
    (unwind-protect
        (progn
          (make-directory modules t)
          (dolist (m my/loader-test--modules)
            (with-temp-file (expand-file-name (concat (nth 0 m) ".el") modules)
              (insert (format ";;; %s.el --- Test module %s -*- lexical-binding: t; -*-\n\n"
                              (nth 0 m) (nth 0 m))
                      (format ";; MyPKS-Requires: %s\n;; MyPKS-Optional: %s\n"
                              (nth 2 m) (nth 1 m))
                      (if (nth 3 m) (format ";; MyPKS-Switch: %s\n" (nth 3 m)) "")
                      "\n;;; Commentary:\n;;; Code:\n"
                      (format "(push %S test-loaded)\n%s\n(provide '%s)\n"
                              (nth 0 m) (nth 4 m) (nth 0 m)))))
          (with-temp-file script
            (insert "(defun check (n ok) (princ (format \"%s %s\\n\" (if ok \"PASS\" \"FAIL\") n)))\n"
                    my/loader-test--checks))
          (with-temp-buffer
            (call-process (expand-file-name invocation-name invocation-directory)
                          nil t nil "-Q" "--batch"
                          ;; A test installs nothing (no-littering, 00-core.el).
                          "--eval" "(setq use-package-ensure-function 'ignore)"
                          "--eval" (format "(setq user-emacs-directory %S)" emacs-dir)
                          "-l" (expand-file-name "modules/00-core.el" my/loader-test--repo)
                          "-l" script)
            (buffer-string)))
      (delete-directory root t))))

(defun my/loader-test--count (string regexp)
  "Count the matches of REGEXP in STRING."
  (with-temp-buffer
    (insert string)
    (how-many regexp (point-min) (point-max))))

(ert-deftest my/loader-test-all ()
  "Every check passes, and all of them ran."
  (let* ((output (my/loader-test--run))
         (passed (my/loader-test--count output "^PASS "))
         (failed (seq-filter (lambda (l) (string-prefix-p "FAIL " l))
                             (split-string output "\n"))))
    (should (null failed))
    (should (= passed 14))))

(provide 'test-loader)
;;; test-loader.el ends here
