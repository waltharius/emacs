;;; 32-web-links.el --- Insert web links with fetched titles -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; MyPKS-Switch: my/web-links-mode

;;; Commentary:
;; Adds one command to fetch a page's <title> and insert it as an
;; Org-mode link: [[URL][Title]]. Uses org-web-tools (MELPA), so this
;; module has no home-grown HTML parsing.
;;
;; Docs: ~/.emacs.d/function_helper.org::#menu-notes-insert

;;; Code:

(use-package org-web-tools
  :ensure t)

(defun my/insert-web-link ()
  "Insert an Org link for a URL, fetching the page title as description.

Prompts for a URL (or reuses the kill-ring/clipboard content if it
looks like one, per `org-web-tools' default behaviour) and inserts
[[URL][Title]] at point."
  (interactive)
  ;; Said in words: without org-web-tools the call failed with
  ;; "wrong-type-argument commandp" (until 2026-10-25).
  (unless (fboundp 'org-web-tools-insert-link-for-url)
    (user-error "org-web-tools is not installed (M-x package-install RET org-web-tools)"))
  (call-interactively #'org-web-tools-insert-link-for-url))

;; In the Link column of the Insert menu, after "L" (12-transient.el).
;; Anchored on "I" (31-org-images.el) until 2026-10-19, so the entry
;; vanished without the images module; a web link is a link anyway.
(defgroup my/web-links nil
  "Web links with fetched titles (32-web-links.el)."
  :tag "Web links"
  :group 'mypks-writing)

;; ============================================================
;; ON AND OFF
;; ============================================================
;; `my/web-links-mode' is this module's switch (module contract, rule
;; 12): on, Web link in the Insert menu (C-c n i u); off, gone.  The
;; commands stay defined for M-x.  Customize saves the position in this
;; machine's settings (M-x customize-option RET my/web-links-mode).

(defconst my/web-links--menu-entries
  '((append my/notes-insert-menu "L" ("u" "Web link (auto title)" my/insert-web-link)))
  "Menu entries of this module, for `my/transient-entries'.")

(define-minor-mode my/web-links-mode
  "Web links as a module, switched on and off.
On: Web link in the Insert menu (C-c n i u).  Off: they are gone, and
the commands remain for M-x.  Customize saves the position in this
machine's settings."
  :global t
  :init-value t
  :group 'my/web-links
  (with-eval-after-load '12-transient
    (when (fboundp 'my/transient-entries)
      (my/transient-entries my/web-links-mode my/web-links--menu-entries))))

(my/web-links-mode (if my/web-links-mode 1 -1))

(provide '32-web-links)
;;; 32-web-links.el ends here
