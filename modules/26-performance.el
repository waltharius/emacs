;;; 26-performance.el --- Performance tuning for a large note collection -*- lexical-binding: t; -*-

;;; Commentary:
;; Settings that only start to matter once the notes tree holds
;; thousands of files and photo-sized attachments.  Everything here is
;; a variable change, not new behaviour, and each one names the cost it
;; removes.
;;
;; Load LAST in init.el, after every module that sets the same
;; variables, so these values win.
;;
;; Measure before and after with:
;;   M-x profiler-start RET cpu RET   ... do the slow thing ...
;;   M-x profiler-report
;; The report names the actual function eating the time; if it is not
;; one of the causes described below, say so rather than adding more
;; settings on a guess.

;;; Code:

;; ============================================================
;; A — DIRED: stop re-listing 3,000-file directories on a timer
;; ============================================================
;; `global-auto-revert-mode' with `global-auto-revert-non-file-buffers'
;; polls every `auto-revert-interval' seconds (default 5) and reverts
;; Dired buffers, which re-runs `ls' on the directory and re-applies
;; `denote-dired-mode' font-lock to every line.  In ~/notes/journal/
;; that is 3,284 long file names, twelve times a minute, whether or not
;; anything changed.
;;
;; `auto-revert-avoid-polling' switches to file-notification watches:
;; buffers revert when the kernel reports a change and stay idle
;; otherwise.  Polling remains as a fallback for files on remote or
;; unsupported filesystems.  This matters more here than in most
;; configurations because Syncthing writes into the notes tree from
;; outside Emacs, so auto-revert is worth keeping - just not on a
;; timer.

(setq auto-revert-avoid-polling t)

;; Even with notifications, a very large Dired buffer is expensive to
;; re-fontify.  Sorting by name (rather than the default `ls' order)
;; and skipping the details columns is already done in 04-denote.el;
;; what remains is to keep Dired from re-reading the directory when it
;; regains focus.
(setq dired-auto-revert-buffer nil)

;; ============================================================
;; B — IMAGES: scale once instead of on every redisplay
;; ============================================================
;; With `org-image-actual-width' unset, Org displays images at their
;; intrinsic size.  A phone photo is 3,000-4,000 px wide, so every
;; screen line of that image is computed against a bitmap far larger
;; than the window, and scrolling past it recomputes window metrics for
;; the whole thing.  This is the usual cause of "notes with photos
;; scroll slowly"; Obsidian sidesteps it because a browser engine
;; rasterises and caches at the displayed size.
;;
;; A fixed width makes Emacs produce one scaled image and reuse it from
;; the image cache.  600 px suits an 80-column centred window; raise it
;; if attachments look soft.  Per-image overrides still work:
;;   #+ATTR_ORG: :width 900
(setq org-image-actual-width '(600))

;; Keep scaled images in the cache long enough to survive scrolling
;; back and forth through a note (default is 300 seconds).
(setq image-cache-eviction-delay 900)

;; Font caches are never compacted while images are on screen; on some
;; builds this compaction is itself a visible pause.
(setq inhibit-compacting-font-caches t)

;; ============================================================
;; C — FONT-LOCK: defer highlighting of off-screen text
;; ============================================================
;; Journal notes are long and `org-hide-emphasis-markers' plus the
;; Denote name faces make fontification non-trivial.  Deferring it
;; slightly means scrolling shows text immediately and highlights it a
;; fraction of a second later, instead of blocking the scroll.

(setq jit-lock-defer-time 0.05)

;; ============================================================
;; D — GC DURING EDITING
;; ============================================================
;; init.el already raises `gc-cons-threshold' to 16 MB after startup.
;; That is a sensible steady-state value; images push allocation rates
;; much higher, so give the collector more room before it pauses.
(setq gc-cons-threshold (* 64 1024 1024))

;; ============================================================
;; E — WHAT IS **NOT** SET HERE, AND WHY
;; ============================================================
;; `denote-infer-keywords' stays t.  It makes Denote read the keyword
;; vocabulary from existing file names, which is what keeps the tag set
;; consistent; turning it off would trade a correctness feature for an
;; unmeasured speedup.  If a profiler report shows keyword inference
;; dominating a prompt, the fix is to pin the vocabulary in
;; `denote-known-keywords' and set `denote-infer-keywords' to nil -
;; but measure first.
;;
;; Nothing here caches `denote-directory-files'.  A stale cache in a
;; tree that Syncthing writes to would show notes that no longer exist,
;; which is a worse failure than a slow prompt.

(provide '26-performance)
;;; 26-performance.el ends here
