;;; 32-web-links.el --- Insert web links with fetched titles -*- lexical-binding: t; -*-
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
  (call-interactively #'org-web-tools-insert-link-for-url))

(with-eval-after-load '12-transient
  (my/transient-append 'my/notes-insert-menu "I"
                       '("u" "Web link (auto title)" my/insert-web-link)))

(provide '32-web-links)
;;; 32-web-links.el ends here
