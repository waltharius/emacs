;;; 03b-fonts.el --- Font configuration with mixed fonts -*- lexical-binding: t; -*-
;;; Commentary:
;; Font configuration:
;; - Default: JetBrains Mono (monospace) for all files
;; - Journal notes: Playpen Sans Hebrew (handwriting style)
;; - Other org files: Keep monospace (explicitly disable variable-pitch)

;;; Code:

;; ============================================================
;; BASE FONTS - Monospace for everything by default
;; ============================================================

(set-face-attribute 'default nil
                    :font "JetBrains Mono-12"
                    :weight 'normal)

(set-face-attribute 'fixed-pitch nil
                    :font "JetBrains Mono-12")

;; Variable pitch font (used only in journal notes)
(set-face-attribute 'variable-pitch nil
                    :font "Playpen Sans Hebrew"
                    :weight 'normal)

;; ============================================================
;; JOURNAL-SPECIFIC FONT SETUP
;; ============================================================

(defun my/journal-font-setup ()
  "Enable handwriting font ONLY for journal notes.
   Other org files EXPLICITLY stay monospace."
  (if (and (buffer-file-name)
           (string-match-p "journal" (buffer-file-name)))
      ;; This IS a journal file - enable handwriting font
      (progn
        (variable-pitch-mode 1)
        (visual-line-mode 1)
        (face-remap-add-relative 'variable-pitch
                                 :family "Playpen Sans Hebrew"
                                 :height 1.0))
    ;; This is NOT a journal file - ensure monospace
    (progn
      (variable-pitch-mode -1)
      (visual-line-mode 1))))

(add-hook 'org-mode-hook 'my/journal-font-setup)

;; ============================================================
;; ORG FACES ARE NOT SET HERE
;; ============================================================
;; This module used to reach into a dozen Org faces with
;; `set-face-attribute'.  It no longer does, for the reasons written out
;; in 11-org-appearance.el: those calls silently overrode custom.el and
;; behaved differently in new frames.
;;
;; What remains here is the font layer proper -- the three base faces
;; above and the per-buffer choice between them.  Which Org face uses
;; which of those fonts is expressed as `:inherit fixed-pitch' or
;; `:inherit variable-pitch' in custom.el, so changing the handwriting
;; font in one place above still changes every face that follows it.
;;
;; In particular `org-quote' inherits `variable-pitch', which is why a
;; quotation renders in the journal handwriting font in every note, while
;; `org-block' inherits `fixed-pitch' and keeps source blocks monospace
;; even inside a journal.

;; ============================================================
;; FONT CACHE COMPACTION
;; ============================================================
;; Emacs never compacts font caches while images are on screen, and on
;; some builds the compaction itself is a visible pause.  Notes here
;; routinely display inline images (see `org-image-actual-width' in
;; 11-org-appearance.el), so the compaction buys nothing and costs a
;; stutter.

(setq inhibit-compacting-font-caches t)

(provide '03b-fonts)
;;; 03b-fonts.el ends here
