;;; test-spelling-languages.el --- ERT tests for choosing the installed dictionaries -*- lexical-binding: t; -*-

;; Tests: 03-spelling

;;; Commentary:

;; `my/spell-languages' (03-spelling.el): for each language the first
;; dictionary Hunspell has.  Until 2026-10-20 the names were fixed to
;; the NixOS ones, "pl_PL,en_GB-large", and on Fedora, Debian or Ubuntu
;; loading flyspell failed ("ispell-phaf: No matching entry for pl_PL").
;;
;; The choice itself is tested without Hunspell; the whole path -- ispell
;; loads, the dictionaries are found, a misspelling is marked -- needs
;; Hunspell with a Polish and an English dictionary (the workflow
;; installs them).
;;
;;   emacs -Q --batch --eval '(package-initialize)' -l ert \
;;     -l tests/test-spelling-languages.el -f ert-run-tests-batch-and-exit
;;
;; or all tests at once: hooks/check-all.

;;; Code:

(require 'ert)
(require 'seq)

(load (expand-file-name "helper" (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(my/test-load-modules "03-spelling")

(defconst my/spell-langs-test--wanted '(("pl_PL") ("en_GB-large" "en_GB" "en_US"))
  "The default languages, spelled out so that the tests do not follow a change.")

(ert-deftest my/spell-langs-test-choose-fedora ()
  "Fedora, Debian, Ubuntu: en_GB and en_US installed, no en_GB-large."
  (should (equal (my/spell--choose my/spell-langs-test--wanted '("pl_PL" "en_US" "en_GB"))
                 '("pl_PL" "en_GB"))))

(ert-deftest my/spell-langs-test-choose-best-first ()
  "The first choice wins when it is installed (NixOS registers en_GB-large)."
  (should (equal (my/spell--choose my/spell-langs-test--wanted '("en_GB" "en_GB-large" "pl_PL"))
                 '("pl_PL" "en_GB-large"))))

(ert-deftest my/spell-langs-test-missing-language-left-out ()
  "A language with no installed dictionary is left out, and named."
  (should (equal (my/spell--choose my/spell-langs-test--wanted '("en_US"))
                 '("en_US")))
  (should (equal (my/spell--missing my/spell-langs-test--wanted '("en_US"))
                 '(("pl_PL")))))

(ert-deftest my/spell-langs-test-installed-dictionaries-used ()
  "With Hunspell: ispell uses installed dictionaries and marks a misspelling."
  (skip-unless (executable-find "hunspell"))
  (require 'flyspell)
  (should (stringp ispell-dictionary))
  (should (string-prefix-p "pl_PL," ispell-dictionary))
  (with-temp-buffer
    (insert "Kot pije mleko. The cat drinks milk. zzzqxv\n")
    (flyspell-mode 1)
    (flyspell-buffer)
    (should (equal (mapcar (lambda (o) (buffer-substring (overlay-start o) (overlay-end o)))
                           (seq-filter #'flyspell-overlay-p
                                       (overlays-in (point-min) (point-max))))
                   '("zzzqxv")))))

(provide 'test-spelling-languages)
;;; test-spelling-languages.el ends here
