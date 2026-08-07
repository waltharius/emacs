#!/usr/bin/env python3
"""Convert Obsidian markdown journal notes to org/Denote journal files.

Usage:
    # Dry run (default): writes ONLY reports, no org files
    python3 convert_journal.py "~/syncthing/Obsidian/00 Daily Notes/00 Finished" ~/notes/journal-migrated

    # Convert a small sample for manual inspection
    python3 convert_journal.py SRC DST --write --limit 20

    # Full conversion
    python3 convert_journal.py SRC DST --write --vault-root ~/syncthing/Obsidian

Requires pandoc on PATH. On NixOS:  nix-shell -p pandoc python3

Output layout:
    DST/                      converted .org files (Denote naming)
    DST/attachments/          images copied and renamed with note ID prefix
    DST/_reports/             TSV reports: conflicts, unresolved links,
                              missing images, trimmed filenames, errors

Never modifies the source vault. Safe to re-run (overwrites DST files).
"""

import argparse
import csv
import datetime as dt
import re
import shutil
import subprocess
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

# ----------------------------------------------------------------------
# CONFIG - decisions encoded here; change if needed
# ----------------------------------------------------------------------

# Max filename length in BYTES (ext4 limit is 255; keep a safety margin).
MAX_FILENAME_BYTES = 180

# 'important: true' in frontmatter becomes an 'important' tag.
IMPORTANT_AS_TAG = True

# Frontmatter keys that are intentionally dropped (Obsidian navigation
# links and metadata that has no place in the org files).
DROPPED_KEYS = {
    "aliases", "creation_date", "day_described", "important",
    "year", "month_ago", "previous_day", "next_day", "next_year",
    "next_month", "in_a_year", "in_a_month",
}
HANDLED_KEYS = DROPPED_KEYS | {"tags", "tag", "well-being"}

# Polish weekday abbreviations matching the user's Emacs locale output
# (Monday..Sunday). Full names used for filename validation.
PL_ABBR = ["pon", "wto", "śro", "czw", "pią", "sob", "nie"]
PL_FULL = ["poniedziałek", "wtorek", "środa", "czwartek",
           "piątek", "sobota", "niedziela"]

# Filename date: DD-MM-YYYY at the start, tolerating a stray space
# before the year (one real file has that typo).
FILENAME_DATE_RE = re.compile(r"^(\d{2})-(\d{2})-\s?(\d{4})")

# First heading time like '# Place name (14:35)'
HEADING_TIME_RE = re.compile(r"^#{1,6}\s+.*\((\d{1,2}):(\d{2})\)\s*$")

# Inline tag: '#something' containing at least one letter (so '#8' or
# markdown headings are not touched). \w is unicode-aware, so Polish
# letters are included.
INLINE_TAG_RE = re.compile(r"(?<![\w#])#((?=[\w/\-]*[^\W\d_])[\w/\-]+)")

# Wikilinks: images ![[...]] and normal [[...]] (image regex must be
# applied first).
IMG_LINK_RE = re.compile(r"!\[\[([^\]\|]+)(?:\|([^\]]*))?\]\]")
WIKI_LINK_RE = re.compile(r"\[\[([^\]\|]+)(?:\|([^\]]*))?\]\]")

# Date patterns accepted inside wikilink targets, in priority order.
LINK_DATE_RES = [
    re.compile(r"(\d{4})-(\d{2})-(\d{2})"),              # YYYY-MM-DD
    re.compile(r"(\d{2})[-.](\d{2})[-.](\d{4})"),        # DD-MM-YYYY / DD.MM.YYYY
]

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg",
              ".bmp", ".pdf", ".mp4", ".mov", ".m4a", ".mp3", ".webm"}

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def check_pandoc():
    if shutil.which("pandoc") is None:
        die("pandoc not found on PATH. On NixOS run inside: nix-shell -p pandoc python3")


def parse_frontmatter(lines):
    """Minimal YAML-ish parser (flat keys, inline and dash lists).
    Returns (dict, index_of_first_body_line)."""
    if not lines or lines[0].strip() != "---":
        return {}, 0
    fm, i, list_key = {}, 1, None
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped in ("---", "..."):
            return fm, i + 1
        if list_key is not None and stripped.startswith("- "):
            fm[list_key].append(stripped[2:].strip().strip("'\""))
            i += 1
            continue
        list_key = None
        m = re.match(r"^([A-Za-z0-9_\- ]+):\s*(.*)$", stripped)
        if m:
            key = m.group(1).strip().lower()
            val = m.group(2).strip()
            if val == "":
                fm[key] = []
                list_key = key
            elif val.startswith("[") and val.endswith("]"):
                fm[key] = [v.strip().strip("'\"")
                           for v in val[1:-1].split(",") if v.strip()]
            else:
                fm[key] = val.strip("'\"")
        i += 1
    return {}, 0  # no closing '---': treat file as frontmatter-less


def normalize_tag(raw):
    """Split nested tags on '/', then for each part: lowercase, keep
    unicode letters and digits, drop every other character (spaces,
    underscores, dashes are concatenated away), per the user's org
    convention. Returns a list of tags."""
    out = []
    for part in str(raw).split("/"):
        part = part.strip().lower()
        # Keep letters (incl. Polish) and digits only.
        tag = "".join(ch for ch in part
                      if unicodedata.category(ch)[0] in ("L", "N"))
        if tag:
            out.append(tag)
    return out


def parse_date_any(s):
    """Parse 'YYYY-MM-DD' or 'DD-MM-YYYY' / 'DD.MM.YYYY' into a date."""
    s = s.strip()
    for rx, order in ((LINK_DATE_RES[0], "ymd"), (LINK_DATE_RES[1], "dmy")):
        m = rx.fullmatch(s) or rx.search(s)
        if m:
            try:
                if order == "ymd":
                    return dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
                return dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
            except ValueError:
                return None
    return None


# Obsidian navigation callout detection: relative-date link aliases
# like [[...|-1y]], [[...|+3m]], [[...|-2d]]
NAV_ALIAS_RE = re.compile(r"\|\s*[+-]\d+\s*[ymd]\s*\]\]")
NAV_MARKER = "w poprzednich znanych wpisach"


def strip_nav_block(body_lines):
    """Remove the Obsidian navigation block that many notes carry
    BEFORE their first heading: a callout/blockquote full of relative
    date links ('W poprzednich znanych wpisach', [[...|-1y]] etc.).
    Detection: any contiguous run of non-empty lines before the first
    heading that contains the marker text or >= 3 relative-date link
    aliases. Returns (new_lines, removed_line_count)."""
    out, removed, i, n = [], 0, 0, len(body_lines)
    seen_heading = False
    while i < n:
        line = body_lines[i]
        if re.match(r"^\s*#{1,6}\s", line):
            seen_heading = True
        if not seen_heading and line.strip():
            j, block = i, []
            while (j < n and body_lines[j].strip()
                   and not re.match(r"^\s*#{1,6}\s", body_lines[j])):
                block.append(body_lines[j])
                j += 1
            blob = "\n".join(block)
            if (NAV_MARKER in blob.lower()
                    or len(NAV_ALIAS_RE.findall(blob)) >= 3):
                removed += len(block)
            else:
                out.extend(block)
            i = j
            continue
        out.append(line)
        i += 1
    return out, removed


def folder_date(path, src, day):
    """Build a date from the folder structure YYYY/'MM month name'/ plus
    a day-of-month taken from the filename. Returns a date or None."""
    try:
        rel_parts = path.relative_to(src).parts
    except ValueError:
        return None
    if len(rel_parts) < 3:
        return None
    ym = re.match(r"^(\d{4})$", rel_parts[-3])
    mm = re.match(r"^(\d{2})\b", rel_parts[-2])
    if not (ym and mm):
        return None
    try:
        return dt.date(int(ym.group(1)), int(mm.group(1)), day)
    except ValueError:
        return None


def org_date_string(date, hh=None, mm=None):
    abbr = PL_ABBR[date.weekday()]
    if hh is None:
        return f"[{date:%Y-%m-%d} {abbr}]"
    return f"[{date:%Y-%m-%d} {abbr} {hh:02d}:{mm:02d}]"


def run_pandoc(md_text):
    """markdown -> org for the note body. --wrap=none keeps original
    line structure instead of re-wrapping at 72 columns."""
    proc = subprocess.run(
        ["pandoc", "-f", "markdown-auto_identifiers", "-t", "org",
         "--wrap=none"],
        input=md_text.encode("utf-8"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace")[:500])
    return proc.stdout.decode("utf-8")


# ----------------------------------------------------------------------
# Main conversion
# ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src", help="Obsidian journal folder (00 Finished)")
    ap.add_argument("dst", help="Output directory for org files")
    ap.add_argument("--vault-root", default=None,
                    help="Directory to search for embedded images "
                         "(default: two levels above SRC)")
    ap.add_argument("--write", action="store_true",
                    help="Actually write org files and copy images. "
                         "Without this flag only reports are produced.")
    ap.add_argument("--limit", type=int, default=None,
                    help="Convert only the first N files (for inspection)")
    args = ap.parse_args()

    check_pandoc()
    src = Path(args.src).expanduser()
    dst = Path(args.dst).expanduser()
    if not src.is_dir():
        die(f"Source is not a directory: {src}")
    vault_root = (Path(args.vault_root).expanduser()
                  if args.vault_root else src.parent.parent)

    reports_dir = dst / "_reports"
    attach_dir = dst / "attachments"
    dst.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(exist_ok=True)
    if args.write:
        attach_dir.mkdir(exist_ok=True)

    # Reports
    conflicts, unresolved_links, missing_images = [], [], []
    trimmed, weekday_mismatch, unknown_keys, errors = [], [], [], []
    nav_removed = []
    converted_map = []

    # Index images in the vault by basename (lowercased) for embeds.
    image_index = {}
    for p in vault_root.rglob("*"):
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS:
            image_index.setdefault(p.name.lower(), p)

    md_files = sorted(src.rglob("*.md"))
    if args.limit:
        md_files = md_files[: args.limit]
    print(f"{len(md_files)} markdown files, image index: {len(image_index)} files, "
          f"mode: {'WRITE' if args.write else 'DRY RUN'}")

    # ---------- PASS 1: dates, ids, collision check ----------
    notes = []           # dicts with parsed info
    date_to_id = {}      # date -> denote id (for link resolution)
    date_seen = defaultdict(list)

    for path in md_files:
        name = path.name
        m = FILENAME_DATE_RE.match(name)
        if not m:
            errors.append((str(path.relative_to(src)),
                           "no DD-MM-YYYY date at start of filename - SKIPPED"))
            continue
        try:
            fdate = dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
        except ValueError:
            errors.append((str(path.relative_to(src)),
                           "invalid date in filename - SKIPPED"))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        fm, body_start = parse_frontmatter(lines)
        body_lines = lines[body_start:]
        rel = str(path.relative_to(src))

        # Date: the filename is the primary source (Obsidian's displayed
        # "title" is rendered from the filename and does not exist in
        # the file content). Some filenames carry a wrong month/year
        # (old locale problems, typos). When the Polish weekday word in
        # the filename contradicts the filename date, try a date rebuilt
        # from the folder path (YYYY/'MM month'/) plus the day from the
        # filename - and use it only if the weekday matches it.
        date = fdate
        wd_in_name = None
        lower_name = name.lower()
        for wd_idx, wd_name in enumerate(PL_FULL):
            if wd_name in lower_name:
                wd_in_name = wd_idx
                break
        if wd_in_name is not None and fdate.weekday() != wd_in_name:
            alt = folder_date(path, src, int(m.group(1)))
            if alt and alt != fdate and alt.weekday() == wd_in_name:
                date = alt
                conflicts.append((rel, f"filename={fdate}",
                                  f"folder+weekday={alt}",
                                  "using folder-derived date"))
            else:
                weekday_mismatch.append(
                    (rel,
                     f"filename says {PL_FULL[wd_in_name]}, but {fdate} "
                     f"is {PL_FULL[fdate.weekday()]}; no folder-derived "
                     "alternative matched - using filename date, "
                     "VERIFY MANUALLY"))

        for key in fm:
            if key not in HANDLED_KEYS:
                unknown_keys.append((rel, key))

        # day_described cross-check (informational only)
        dd_raw = fm.get("day_described", "")
        if isinstance(dd_raw, list):
            dd_raw = dd_raw[0] if dd_raw else ""
        if str(dd_raw).strip():
            dd = parse_date_any(str(dd_raw))
            if dd and dd != date:
                conflicts.append((rel,
                                  f"chosen={date}", f"day_described={dd}",
                                  "using chosen date"))

        # Time from first heading
        hh = mm = None
        for line in body_lines:
            if line.lstrip().startswith("#"):
                hm = HEADING_TIME_RE.match(line.strip())
                if hm:
                    hh, mm = int(hm.group(1)), int(hm.group(2))
                break

        if hh is not None:
            ident = f"{date:%Y%m%d}T{hh:02d}{mm:02d}00"
        else:
            ident = f"{date:%Y%m%d}T000000"

        date_seen[date].append(name)
        notes.append(dict(path=path, date=date, fm=fm,
                          body_lines=body_lines, hh=hh, mm=mm, ident=ident))

    collisions = {d: names for d, names in date_seen.items() if len(names) > 1}
    if collisions:
        print("\nFATAL: multiple notes share the same date - fix these in the "
              "vault first (see duplicate dates below), then re-run:")
        for d, names in sorted(collisions.items()):
            print(f"  {d}: {names}")
        # Still write reports gathered so far, then stop.
        write_reports(reports_dir, conflicts, unresolved_links, missing_images,
                      trimmed, weekday_mismatch, unknown_keys, errors,
                      converted_map, nav_removed)
        sys.exit(2)

    for n in notes:
        date_to_id[n["date"]] = n["ident"]

    # ---------- PASS 2: convert ----------
    for n in notes:
        rel = str(n["path"].relative_to(src))
        try:
            org_text, note_reports = convert_note(
                n, date_to_id, image_index, attach_dir, args.write)
        except Exception as e:  # keep going, log the failure
            errors.append((rel, f"conversion failed: {e}"))
            continue
        unresolved_links += note_reports["unresolved"]
        missing_images += note_reports["missing_images"]
        if note_reports["nav_lines_removed"]:
            nav_removed.append((rel, note_reports["nav_lines_removed"]))

        # Tags and filename
        tags = collect_tags(n["fm"], note_reports["inline_tags"])
        keywords = sorted(set(tags) | {"journal"})
        filetags = ":" + ":".join(keywords) + ":"

        fname_keywords = list(keywords)
        base = f"{n['ident']}--{n['date']:%Y-%m-%d}-journal"
        def build_name(kws):
            return f"{base}__{'_'.join(kws)}.org"
        fname = build_name(fname_keywords)
        dropped_kws = []
        while len(fname.encode("utf-8")) > MAX_FILENAME_BYTES and len(fname_keywords) > 1:
            candidates = [k for k in fname_keywords if k != "journal"]
            longest = max(candidates, key=len)
            fname_keywords.remove(longest)
            dropped_kws.append(longest)
            fname = build_name(fname_keywords)
        if dropped_kws:
            trimmed.append((rel, fname, "dropped from filename: "
                            + ", ".join(dropped_kws),
                            "full tags kept in #+filetags"))

        # Frontmatter (exact spacing copied from the user's Emacs functions)
        wb = n["fm"].get("well-being", "")
        if isinstance(wb, list):
            wb = wb[0] if wb else ""
        head = (
            f"#+title:      {n['date']:%Y-%m-%d} Journal\n"
            f"#+date:       {org_date_string(n['date'], n['hh'], n['mm'])}\n"
            f"#+filetags:   {filetags}\n"
            f"#+identifier: {n['ident']}\n"
            ":PROPERTIES:\n"
            f":well-being:  {str(wb).strip()}\n"
            ":END:\n\n"
        )

        out_path = dst / fname
        if args.write:
            out_path.write_text(head + org_text.lstrip("\n"), encoding="utf-8")
        converted_map.append((rel, fname, n["ident"]))

    write_reports(reports_dir, conflicts, unresolved_links, missing_images,
                  trimmed, weekday_mismatch, unknown_keys, errors,
                  converted_map, nav_removed)

    print(f"\nDone. Converted: {len(converted_map)} / {len(md_files)}")
    print(f"Reports in {reports_dir}:")
    print(f"  date conflicts:      {len(conflicts)}")
    print(f"  weekday mismatches:  {len(weekday_mismatch)}")
    print(f"  unresolved links:    {len(unresolved_links)}")
    print(f"  missing images:      {len(missing_images)}")
    print(f"  trimmed filenames:   {len(trimmed)}")
    print(f"  unknown fm keys:     {len(unknown_keys)}")
    print(f"  nav blocks removed:  {len(nav_removed)}")
    print(f"  errors:              {len(errors)}")
    if not args.write:
        print("\nDRY RUN - no org files were written. Re-run with --write.")


def collect_tags(fm, inline_tags):
    tags = []
    raw = fm.get("tags", fm.get("tag", []))
    if isinstance(raw, str):
        raw = [t for t in re.split(r"[,\s]+", raw) if t]
    for t in raw:
        tags += normalize_tag(t)
    for t in inline_tags:
        tags += normalize_tag(t)
    if IMPORTANT_AS_TAG and str(fm.get("important", "")).lower() == "true":
        tags.append("important")
    return tags


def convert_note(n, date_to_id, image_index, attach_dir, do_write):
    """Convert one note body. Wikilinks and image embeds are replaced by
    placeholders before pandoc and restored afterwards, so pandoc never
    sees (and never mangles) them."""
    body_lines, nav_lines_removed = strip_nav_block(n["body_lines"])
    body = "\n".join(body_lines)
    placeholders = {}
    counter = [0]
    unresolved, missing_images, inline_tags = [], [], []
    rel = n["path"].name

    def stash(replacement_org):
        counter[0] += 1
        token = f"QQPLACEHOLDER{counter[0]:04d}QQ"
        placeholders[token] = replacement_org
        return token

    # 1) image embeds ![[file]] / ![[file|size]]
    def repl_img(m):
        target = m.group(1).strip()
        # Obsidian display parameters after '#' (e.g.
        # '#supernote-invert-dark') are not part of the file name.
        clean = target.split("#")[0].strip()
        if Path(clean).suffix.lower() not in IMAGE_EXTS:
            # ![[Some note]] is a note transclusion, not an attachment -
            # keep it as a literal wikilink and log it with the other
            # unresolved links.
            unresolved.append((rel, clean, "(transclusion)"))
            return stash(f"[[{clean}]]")
        found = image_index.get(Path(clean).name.lower())
        if not found:
            missing_images.append((rel, clean))
            return stash(f"[[{clean}]] (missing attachment)")
        # Replace spaces in the original name so org file: links stay clean
        new_name = f"{n['ident']}--{found.name.replace(' ', '-')}"
        if do_write:
            shutil.copy2(found, attach_dir / new_name)
        return stash(f"[[file:attachments/{new_name}]]")
    body = IMG_LINK_RE.sub(repl_img, body)

    # 2) wikilinks [[target]] / [[target|alias]]
    def repl_link(m):
        target = m.group(1).strip()
        alias = (m.group(2) or "").strip()
        # strip a #heading fragment for resolution
        target_base = target.split("#")[0].strip()
        d = parse_date_any(target_base)
        if d and d in date_to_id:
            desc = alias or target
            return stash(f"[[denote:{date_to_id[d]}][{desc}]]")
        unresolved.append((rel, target, alias))
        original = f"[[{target}|{alias}]]" if alias else f"[[{target}]]"
        return stash(original)
    body = WIKI_LINK_RE.sub(repl_link, body)

    # 3) inline tags: collect, then strip the '#' (outside code fences,
    #    skipping markdown headings)
    out_lines, in_code = [], False
    for line in body.splitlines():
        if line.strip().startswith("```"):
            in_code = not in_code
            out_lines.append(line)
            continue
        if in_code or re.match(r"^\s*#{1,6}\s", line):
            out_lines.append(line)
            continue
        for tm in INLINE_TAG_RE.finditer(line):
            inline_tags.append(tm.group(1))
        out_lines.append(INLINE_TAG_RE.sub(r"\1", line))
    body = "\n".join(out_lines)

    # 4) pandoc
    org = run_pandoc(body)

    # 5) restore placeholders
    for token, replacement in placeholders.items():
        org = org.replace(token, replacement)

    return org, dict(unresolved=unresolved, missing_images=missing_images,
                     inline_tags=inline_tags,
                     nav_lines_removed=nav_lines_removed)


def write_reports(reports_dir, conflicts, unresolved_links, missing_images,
                  trimmed, weekday_mismatch, unknown_keys, errors,
                  converted_map, nav_removed):
    def tsv(name, header, rows):
        with (reports_dir / name).open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, delimiter="\t")
            w.writerow(header)
            w.writerows(rows)
    tsv("date_conflicts.tsv",
        ["file", "filename_date", "day_described", "resolution"], conflicts)
    tsv("weekday_mismatches.tsv", ["file", "detail"], weekday_mismatch)
    tsv("unresolved_links.tsv", ["file", "link_target", "alias"],
        unresolved_links)
    tsv("missing_images.tsv", ["file", "image"], missing_images)
    tsv("trimmed_filenames.tsv", ["file", "final_name", "dropped", "note"],
        trimmed)
    tsv("unknown_frontmatter_keys.tsv", ["file", "key"], unknown_keys)
    tsv("errors.tsv", ["file", "error"], errors)
    tsv("converted_map.tsv", ["source_md", "org_filename", "identifier"],
        converted_map)
    tsv("nav_blocks_removed.tsv", ["file", "lines_removed"], nav_removed)


if __name__ == "__main__":
    main()
