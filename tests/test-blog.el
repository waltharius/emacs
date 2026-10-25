;;; test-blog.el --- ERT tests for 746-blog -*- lexical-binding: t; -*-

;; Tests: 746-blog

;;; Commentary:

;; What 746-blog.el does that is not a rule of SAFETY.org (those are in
;; test-safety.el).  Starts with the restart of a running Hugo server
;; after its theme is reinstalled (2026-10-20).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-blog.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "746-blog")

(ert-deftest my/blog-test-server-restarted-after-theme-install ()
  "A `hugo server' running for a site is restarted when its theme is
installed again, with the same following of changes; a site with another
theme is left alone."
  (let* ((dir (file-name-as-directory (make-temp-file "mypks-site-" t)))
         (my/blog-sites `(("s" :directory ,dir :theme ("T" "https://example.org/t"))
                          ("o" :directory ,dir :theme ("Other" "https://example.org/o"))))
         (restarted nil)
         ;; Stand-ins for two running servers: a process in each
         ;; preview buffer, the first started with --navigateToChanged.
         (proc (make-process :name "blog-test-s" :buffer (my/blog--preview-buffer "s")
                             :command '("sh" "-c" "sleep 30" "x" "--navigateToChanged")
                             :noquery t))
         (other (make-process :name "blog-test-o" :buffer (my/blog--preview-buffer "o")
                              :command '("sleep" "30") :noquery t)))
    (unwind-protect
        (cl-letf (((symbol-function 'my/blog--serve)
                   (lambda (name follow) (push (list name follow) restarted))))
          (my/blog--theme-install-done (expand-file-name "themes/T" dir) t)
          (should-not (process-live-p proc))
          (should (process-live-p other))
          (with-timeout (5 (error "The server was not started again"))
            (while (not restarted)
              (accept-process-output nil 0.1)))
          (should (equal restarted '(("s" t)))))
      (when (process-live-p other) (delete-process other))
      (when (process-live-p proc) (delete-process proc))
      (delete-directory dir t))))

(ert-deftest my/blog-test-failed-install-restarts-nothing ()
  "A theme that failed to install leaves the running server alone."
  (let* ((dir (file-name-as-directory (make-temp-file "mypks-site-" t)))
         (my/blog-sites `(("s" :directory ,dir :theme ("T" "https://example.org/t"))))
         (proc (make-process :name "blog-test-s" :buffer (my/blog--preview-buffer "s")
                             :command '("sleep" "30") :noquery t)))
    (unwind-protect
        (progn
          (my/blog--theme-install-done (expand-file-name "themes/T" dir) nil)
          (should (process-live-p proc)))
      (when (process-live-p proc) (delete-process proc))
      (delete-directory dir t))))

(provide 'test-blog)
;;; test-blog.el ends here
