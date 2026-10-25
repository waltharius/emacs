# Bundled CSL files

A citation style and two locales, so that citation export works on a
fresh installation, before any style has been put next to the notes.
Used only when the folders named by `my/csl-styles-dir` and
`my/csl-locales-dir` (17-bibliography.el) lack the file in question;
files there always win.

| File                                      | Source                                                        | Updated (in file) |
|-------------------------------------------|---------------------------------------------------------------|-------------------|
| `styles/chicago-notes-bibliography.csl`   | https://github.com/citation-style-language/styles             | 2025-02-09        |
| `locales/locales-pl-PL.xml`               | https://github.com/citation-style-language/locales            | 2026-01-10        |
| `locales/locales-en-US.xml`               | https://github.com/citation-style-language/locales            | 2026-01-10        |

Downloaded unchanged on 2026-10-14 from the `master` branches.

`styles/mypks-short-reference.csl` is not from these repositories: it
is this configuration's own style for the short reference `C-c x S`
inserts into a note (17-bibliography.el, `my/reference-short-style`),
under the licence of this repository.  Used for that only, never for
export.

## Licence

These files (all but `mypks-short-reference.csl`) are not covered by the licence of this repository.  They
are the work of the Citation Style Language project and its
contributors, licensed under the Creative Commons
Attribution-ShareAlike 3.0 Unported licence
(https://creativecommons.org/licenses/by-sa/3.0/), as stated in the
`<rights>` element of each file.  Authors and contributors are listed in
each file's `<info>` element.

To update, download the same files again from the repositories above
and change the dates in the table.
