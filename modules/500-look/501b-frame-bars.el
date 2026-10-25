;;; 501b-frame-bars.el --- Tool bar and scroll bar off, menu bar on -*- lexical-binding: t; -*-

;; MyPKS-Requires:
;; MyPKS-Optional: yes
;; Docs: ~/.emacs.d/function_helper.org::#frame-bars

;;; Commentary:

;; The frame's bars: which bars Emacs draws around the text.  Part of
;; the look (group 500 of MODULES.org), split from 101-ui.el on
;; 2026-10-25zc, named 01b-frame-chrome until 2026-10-25zf ("chrome", the
;; interface around the content, read as the browser).  Without this module Emacs draws its own defaults: tool
;; bar, menu bar and scroll bars all on.
;;
;; The tool bar and the scroll bar are the two elements that date the
;; frame most: a row of 16-pixel icons for commands this configuration
;; reaches through C-c n, and a scroll bar duplicating information the
;; mode line already gives as a percentage.  Neither is ever clicked
;; here, and both eat space that the centred text column of
;; 510-visual-fill.el then has to give back.
;;
;; The menu bar STAYS.  It is the only surface that lists what a mode
;; can do without knowing a key for it, which matters in a
;; configuration this large -- Org's own menu alone is a reference.
;; That is a different argument from the one against the tool bar, and
;; it comes out the other way.
;;
;; To revert either for one session: `M-x tool-bar-mode',
;; `M-x scroll-bar-mode'; for good, turn this module off in the
;; settings menu (my/modules-off).

;;; Code:

(defun my/frame-bars-apply ()
  "Turn the tool bar and the scroll bars off.
Run at load and from `desktop-after-read-hook', since a restored
desktop brings back the bars it was saved with; a no-op when they are
already off, so it is safe to call at any time.  An Emacs built
without a window system (Fedora's emacs-nox) has no `scroll-bar-mode':
calling it stopped the start-up there (found 2026-10-22)."
  (tool-bar-mode -1)
  (when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1)))

(my/frame-bars-apply)
(menu-bar-mode 1)

;; THE BARS SURVIVE A DESKTOP RESTORE, AND HAVE TO BE PUT BACK
;; ----------------------------------------------------------
;; `desktop-restore-frames' is t by default, and the frameset it saves
;; includes `tool-bar-lines' and `vertical-scroll-bars'.  Restoring the
;; frameset (101-ui.el saves and reads the session) re-applies whatever
;; those were when the desktop was last saved -- for a desktop written
;; before the tool bar was turned off, the tool bar comes back on every
;; start.  Frameset restore overrides `default-frame-alist' too, so
;; setting the parameters there is not a fix either; re-asserting after
;; the restore is.  The hook needs no desktop loaded: without
;; 101-ui.el's session it is never run.
(add-hook 'desktop-after-read-hook #'my/frame-bars-apply)

(provide '501b-frame-bars)
;;; 501b-frame-bars.el ends here
