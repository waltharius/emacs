#!/usr/bin/env python3
"""Import notes written in Obsidian on the phone into the org/Denote silos.

Counterpart of convert_journal.py, which was a one-shot migration of an
archive.  This one runs repeatedly on a small inbox folder and merges
into files that already exist, which is a different problem: the target
may be open in Emacs, may already hold an '* Obsidian' heading from an
earlier run, and the source must leave the inbox afterwards so that the
next run does not see it again.

Usage:
    # Dry run (default): reports what would happen, writes nothing
    python3 obsidian_import.py

    # Do it
    python3 obsidian_import.py --write

    # Other vault or notes tree
    python3 obsidian_import.py --vault ~/syncthing/Obsidian --notes ~/notes

Requires pandoc and PyYAML.  On NixOS:
    nix-shell -p pandoc python3Packages.pyyaml

Routing:
    YYYY-MM-DD.md            -> ~/notes/journal/, merged under '* Obsidian'
    everything else          -> ~/notes/inbox/, reviewed by 25-inbox-review.el

After a successful import the markdown file moves to
VAULT/Imported2Emacs/<YYYY>/, the year directory being created on demand.
Attachments are COPIED, not moved, so links in the vault keep resolving.
"""

import argparse
import datetime as dt
import re
import shutil
import subprocess
import sys
import time
import unicodedata
from pathlib import Path
from urllib.parse import unquote

try:
    import yaml
except ImportError:                                     # pragma: no cover
    sys.exit("PyYAML is required: nix-shell -p python3Packages.pyyaml")

# ----------------------------------------------------------------------
# CONFIG - decisions encoded here; change if needed
# ----------------------------------------------------------------------

VAULT_DEFAULT = "~/syncthing/Obsidian"
NOTES_DEFAULT = "~/notes"

# Folder Obsidian's Daily notes plugin writes into, and the basket every
# imported file moves to (year subfolder added automatically).
INBOX_REL = "10 Emacs Inbox"
IMPORTED_REL = "Imported2Emacs"

# Silos inside the notes tree.
JOURNAL_REL = "journal"
INBOX_SILO_REL = "inbox"
ATTACH_REL = "attachments"

# Pandoc extensions disabled on purpose.  yaml_metadata_block eats any
# '---' fenced section mid-document; blank_before_header and
# blank_before_blockquote silently flatten a heading or a quote that has
# no blank line above it.  All three corrupted output during the 2026-07
# migration; convert_journal.py in this repository still carries the
# unfixed flags and must not be used as the model here.
PANDOC_FLAGS = ("markdown-auto_identifiers-yaml_metadata_block"
                "-blank_before_header-blank_before_blockquote")

# Tags the daily template always writes; carrying them over would add
# nothing a file name and a silo do not already say.
IGNORED_TAGS = {"journal", "obsidian"}

# Files younger than this are skipped: Syncthing may still be writing
# them, or the phone may still have the note open.  --settle 0 disables.
SETTLE_SECONDS = 60

# ext4 allows 255 bytes; Polish letters take two, so keep a margin.
MAX_FILENAME_BYTES = 180

# Heading imported material is filed under, and the journal front matter
# this configuration writes (see my/denote-journal in 05-notes.el).
OBSIDIAN_HEADING = "Obsidian"
SCHEMA_VERSION = 2
LANGUAGE = "pl"

# Polish weekday abbreviations, Monday first, matching the Emacs locale.
PL_ABBR = ["pon", "wto", "śro", "czw", "pią", "sob", "nie"]

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg",
              ".bmp", ".tiff", ".avif"}

ISO_DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
CONFLICT_RE = re.compile(r"\.sync-conflict-")

# '# (00:16)' from the daily template, and the '---' the template puts
# under it.  That rule is why the heading has to be repaired at all: an
# ATX heading followed directly by '---' is read by pandoc as a setext
# underline, turning the whole line into the TEXT of a level-2 heading
# ('** # (00:16)').  Removing the rule before pandoc sees it is what
# makes the heading a heading.
TEMPLATE_RULE_RE = re.compile(r"(?m)^(#{1,6} .*)\n-{3,}[ \t]*$")
CALLOUT_RE = re.compile(r"(?m)^>[ \t]*\[!(\w+)\][ \t]*(.*)$")
TIME_HEADING_RE = re.compile(r"(?m)^(\*+)[ \t]+\((\d{1,2}):(\d{2})\)[ \t]*$")
ORG_HEADING_RE = re.compile(r"(?m)^(\*+)(?= )")
# Org link syntax is [[target][description]] - the description sits
# INSIDE the outer brackets, which is what makes the naive
# '\\[\\[file:...\\]\\]' pattern miss every described link.
ORG_FILE_LINK_RE = re.compile(r"\[\[file:([^\]\[]+)\](?:\[([^\]]*)\])?\]")


# ----------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------

def die(msg):
    sys.exit(f"FATAL: {msg}")


def check_pandoc():
    try:
        subprocess.run(["pandoc", "--version"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       check=True)
    except (OSError, subprocess.CalledProcessError):
        die("pandoc not found on PATH (nix-shell -p pandoc)")


def org_timestamp(when, with_time=True):
    """Return an inactive org timestamp with a Polish weekday."""
    abbr = PL_ABBR[when.weekday()]
    if with_time and isinstance(when, dt.datetime):
        return f"[{when:%Y-%m-%d} {abbr} {when:%H:%M}]"
    return f"[{when:%Y-%m-%d} {abbr}]"


def normalize_tag(raw):
    """Flatten a nested tag and drop separators, as the migration did.

    'praca/projekt' yields two tags; 'wybory_2023' becomes 'wybory2023',
    because an underscore inside a Denote keyword would split it into two
    keywords in the file name.
    """
    out = []
    for part in str(raw).split("/"):
        part = re.sub(r"[_\-\s]+", "", part.strip()).lower()
        if part:
            out.append(part)
    return out


def slugify(title):
    """Return a Denote-style slug, Polish letters kept.

    Denote lowercases and joins with hyphens; diacritics are preserved
    here because the notes migrated in 2026-07 carry them and a second
    convention would make two files for one title look unrelated.
    """
    text = unicodedata.normalize("NFC", title).lower()
    text = re.sub(r"[^\w-]+", "-", text, flags=re.UNICODE)
    text = re.sub(r"-{2,}", "-", text).strip("-")
    while len(text.encode("utf-8")) > MAX_FILENAME_BYTES:
        text = text.rsplit("-", 1)[0] if "-" in text else text[:-1]
    return text or "notatka"


def parse_frontmatter(text):
    """Split a note into (frontmatter dict, body string).

    YAML is parsed by PyYAML rather than by hand: quoting, colons inside
    values and the several list forms Obsidian writes are exactly where a
    hand-rolled parser fails silently, and silent failure here means a
    wrong date on a real note.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            raw = "\n".join(lines[1:i])
            try:
                data = yaml.safe_load(raw) or {}
            except yaml.YAMLError:
                data = {}
            if not isinstance(data, dict):
                data = {}
            return data, "\n".join(lines[i + 1:])
    return {}, text


def frontmatter_tags(fm):
    """Return normalized tags from the 'tags' key, inline or block form."""
    raw = fm.get("tags") or fm.get("tag") or []
    if isinstance(raw, str):
        raw = re.split(r"[,\s]+", raw)
    tags = []
    for item in raw:
        for tag in normalize_tag(item):
            if tag not in tags:
                tags.append(tag)
    return tags


def parse_created(fm, fallback_path):
    """Return the creation timestamp: 'created', then 'date', then mtime.

    The daily template writes seconds ('YYYY-MM-DDTHH:mm:ss') so that the
    Denote identifier is exact.  Notes made with the older template have
    minutes only and get :00, which is accurate to what was recorded
    rather than invented.
    """
    value = fm.get("created")
    if isinstance(value, dt.datetime):
        return value
    if isinstance(value, dt.date):
        return dt.datetime.combine(value, dt.time())
    if isinstance(value, str):
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M",
                    "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
            try:
                return dt.datetime.strptime(value.strip(), fmt)
            except ValueError:
                continue
    date = parse_date(fm.get("date"))
    if date:
        return dt.datetime.combine(date, dt.time())
    return dt.datetime.fromtimestamp(fallback_path.stat().st_mtime)


def parse_date(value):
    """Return a date from a YAML date or an ISO string, else None."""
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    if isinstance(value, str):
        match = ISO_DATE_RE.match(value.strip())
        if match:
            try:
                return dt.date(*(int(g) for g in match.groups()))
            except ValueError:
                return None
    return None


# ----------------------------------------------------------------------
# Markdown -> org
# ----------------------------------------------------------------------

def preprocess(body):
    """Repair the two Obsidian constructs pandoc cannot read correctly."""
    # The template's horizontal rule, which would turn the time heading
    # into setext-underlined text.  Only a rule directly under a heading
    # is removed; a rule the note itself contains is left alone.
    body = TEMPLATE_RULE_RE.sub(r"\1", body)

    # Callouts: '> [!NOTE] Title' is not blockquote syntax pandoc knows,
    # so the marker and the title end up glued to the first line of the
    # quote.  Rewriting to a bold first line keeps both visible.
    def callout(match):
        label = match.group(2).strip() or match.group(1).capitalize()
        return f"> **{label}**\n>"
    return CALLOUT_RE.sub(callout, body)


def run_pandoc(md_text):
    """Convert markdown to org.

    --wrap=none keeps paragraphs on one line, which is how this
    configuration writes org: a paragraph is one line and Emacs wraps it
    on screen.
    """
    proc = subprocess.run(
        ["pandoc", "-f", PANDOC_FLAGS, "-t", "org", "--wrap=none"],
        input=md_text.encode("utf-8"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace")[:500])
    return proc.stdout.decode("utf-8")


def demote(org_text, levels=1):
    """Add LEVELS stars to every heading, keeping the body in one subtree."""
    if levels <= 0:
        return org_text
    return ORG_HEADING_RE.sub(lambda m: "*" * levels + m.group(1), org_text)


def clean_time_headings(org_text):
    """Turn '** (00:16)' into '** 00:16'.

    The parentheses come from the Obsidian template; journal entries
    written in Emacs are headed by a bare HH:MM and the two should look
    the same once merged.
    """
    return TIME_HEADING_RE.sub(r"\1 \2:\3", org_text)


def rewrite_links(org_text, note_rel_dir, vault, attach_dir,
                  attach_link_base, ident, copies, report):
    """Resolve vault-relative file: links produced by pandoc.

    Images are copied into the shared attachments directory and linked
    with an absolute '~/notes/attachments/' path, which is the form the
    migrated notes already use.  Anything else inside the vault keeps
    pointing at the vault, because the vault is where it still lives.
    Web links are untouched: pandoc already emits them as org links.
    """
    def replace(match):
        target = match.group(1)
        desc = match.group(2)
        if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
            return match.group(0)
        rel = unquote(target)
        candidates = [vault / rel, vault / note_rel_dir / rel]
        source = next((c for c in candidates if c.is_file()), None)
        if source is None:
            report.append(("missing-link", rel))
            return match.group(0)
        if source.suffix.lower() in IMAGE_EXTS:
            new_name = f"{ident}--{source.name}"
            copies.append((source, attach_dir / new_name))
            link = f"{attach_link_base}/{new_name}"
            return f"[[file:{link}]" + (f"[{desc}]" if desc else "") + "]"
        vault_link = f"{vault}/{rel}"
        report.append(("vault-link", rel))
        return f"[[file:{vault_link}]" + (f"[{desc}]" if desc else "") + "]"

    return ORG_FILE_LINK_RE.sub(replace, org_text)


# ----------------------------------------------------------------------
# Journal targets
# ----------------------------------------------------------------------

def journal_keywords(path):
    """Return the Denote keywords encoded in a file name."""
    base = path.stem
    if "__" in base:
        return base.split("__", 1)[1].split("_")
    return []


def journal_file_date(path):
    """Return the date a journal file describes, or None.

    Mirrors my/journal-file-date in 05-notes.el: the 'journal' keyword
    identifies the file, the date comes from the slug and falls back to
    the identifier.  The title is deliberately not consulted.
    """
    if "journal" not in journal_keywords(path):
        return None
    base = path.name
    match = re.search(r"--(\d{4}-\d{2}-\d{2})", base)
    if match:
        try:
            return dt.date.fromisoformat(match.group(1))
        except ValueError:
            pass
    match = re.match(r"^(\d{4})(\d{2})(\d{2})T", base)
    if match:
        try:
            return dt.date(*(int(g) for g in match.groups()))
        except ValueError:
            return None
    return None


def find_journal(journal_dir, date):
    """Return the journal file for DATE, or None."""
    if not journal_dir.is_dir():
        return None
    for path in sorted(journal_dir.glob("*.org")):
        if journal_file_date(path) == date:
            return path
    return None


def existing_identifiers(notes_dir):
    """Return every Denote identifier currently used in the notes tree."""
    idents = set()
    for path in notes_dir.rglob("*.org"):
        if "/." in str(path):
            continue
        match = re.match(r"^(\d{8}T\d{6})", path.name)
        if match:
            idents.add(match.group(1))
    return idents


def unique_identifier(created, taken):
    """Return an unused identifier, bumping by seconds on collision.

    Same rule as my/denote-fix-duplicates in 27-denote-identifiers.el:
    seconds move, the date never does.
    """
    stamp = created
    for _ in range(86400):
        ident = stamp.strftime("%Y%m%dT%H%M%S")
        if ident not in taken:
            taken.add(ident)
            return ident
        stamp += dt.timedelta(seconds=1)
    die(f"no free identifier near {created}")


def journal_front_matter(date, created, ident):
    """Return the front matter of a fresh journal file.

    Metrics keywords are not written: my/journal-set-metrics adds them
    later, and a placeholder here would be a second thing to keep in sync.
    """
    return (f"#+title:      {date.isoformat()}\n"
            f"#+date:       {org_timestamp(created)}\n"
            f"#+filetags:   :journal:\n"
            f"#+identifier: {ident}\n"
            f"#+language:   {LANGUAGE}\n"
            f"#+schema:     {SCHEMA_VERSION}\n\n")


def obsidian_block(body, source_rel, now, tags, nested):
    """Return the subtree imported material is filed under.

    NESTED means the target already carries an '* Obsidian' heading from
    an earlier run.  The drawer then goes on the entry's own time heading
    instead of on a second '* Obsidian', so that provenance is recorded
    per import rather than once per file.
    """
    props = [":PROPERTIES:",
             f":SOURCE:      {source_rel}",
             f":IMPORTED_AT: {org_timestamp(now)}"]
    if tags:
        props.append(f":OBSIDIAN_TAGS: {' '.join(tags)}")
    props.append(":END:")
    drawer = "\n".join(props)
    body = body.rstrip()
    if not nested:
        return f"* {OBSIDIAN_HEADING}\n{drawer}\n\n{body}\n"
    lines = body.split("\n")
    if lines and re.match(r"^\*\* ", lines[0]):
        rest = lines[1:]
        while rest and not rest[0].strip():
            rest.pop(0)
        return "\n".join([lines[0], drawer, ""] + rest) + "\n"
    # No heading of its own: one is added, because a properties drawer
    # with nothing above it would attach to whatever precedes it.
    return f"** Import {org_timestamp(now)}\n{drawer}\n\n{body}\n"


def insert_into_journal(text, block, nested):
    """Return the journal text with BLOCK added.

    With NESTED, the material goes at the end of the existing '* Obsidian'
    subtree rather than at the end of the file, so that everything
    imported from the phone stays in one place however many runs it took.
    """
    text = text.rstrip() + "\n"
    if not nested:
        return text + "\n" + block
    lines = text.split("\n")
    start = next(i for i, line in enumerate(lines)
                 if line.strip() == f"* {OBSIDIAN_HEADING}")
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^\* ", lines[i]):
            end = i
            break
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1
    merged = lines[:end] + ["", block.rstrip()] + lines[end:]
    return "\n".join(merged).rstrip() + "\n"


def inbox_note_text(title, created, ident, tags, source_rel, body):
    """Return a complete inbox note, ready for 25-inbox-review.el.

    The file-level properties drawer carries :source_path: and :status:,
    which are the two fields that module reads besides the front matter.
    """
    filetags = "".join(f":{tag}" for tag in tags) + ":" if tags else ":inbox:"
    return (f"#+title:      {title}\n"
            f"#+date:       {org_timestamp(created)}\n"
            f"#+filetags:   {filetags}\n"
            f"#+identifier: {ident}\n"
            f"#+language:   {LANGUAGE}\n"
            ":PROPERTIES:\n"
            f":source_path: {source_rel}\n"
            ":status:      new\n"
            ":END:\n\n"
            f"{body.rstrip()}\n")


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def collect_sources(inbox_dir, settle):
    """Return the markdown files worth importing, oldest first."""
    if not inbox_dir.is_dir():
        die(f"inbox folder not found: {inbox_dir}")
    now = time.time()
    out = []
    for path in sorted(inbox_dir.rglob("*.md")):
        if CONFLICT_RE.search(path.name):
            continue
        if any(part.startswith(".") for part in path.parts):
            continue
        if settle and now - path.stat().st_mtime < settle:
            continue
        out.append(path)
    return sorted(out, key=lambda p: p.name)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", default=VAULT_DEFAULT)
    ap.add_argument("--notes", default=NOTES_DEFAULT)
    ap.add_argument("--write", action="store_true",
                    help="actually write, move and copy (default: dry run)")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--settle", type=int, default=SETTLE_SECONDS,
                    help="skip files modified in the last N seconds")
    ap.add_argument("--report", help="write the org report to this file")
    ap.add_argument("--touched",
                    help="write one path per line for every org file "
                         "created or modified (read by Emacs to revert them)")
    args = ap.parse_args()

    check_pandoc()
    vault = Path(args.vault).expanduser().resolve()
    notes = Path(args.notes).expanduser()
    inbox_dir = vault / INBOX_REL
    journal_dir = notes / JOURNAL_REL
    inbox_silo = notes / INBOX_SILO_REL
    attach_dir = notes / ATTACH_REL
    imported_dir = vault / IMPORTED_REL
    # Attachment links are written with a '~/' prefix, the way the notes
    # migrated in 2026-07 carry them, so they keep resolving if the home
    # directory ever moves.  Outside the home directory there is nothing
    # to abbreviate and the absolute path is used as is.
    attach_abs = attach_dir.expanduser().resolve()
    home = Path.home().resolve()
    try:
        attach_link_base = "~/" + attach_abs.relative_to(home).as_posix()
    except ValueError:
        attach_link_base = attach_abs.as_posix()

    if not vault.is_dir():
        die(f"vault not found: {vault}")
    if not journal_dir.is_dir():
        die(f"journal silo not found: {journal_dir}")

    sources = collect_sources(inbox_dir, args.settle)
    if args.limit:
        sources = sources[:args.limit]
    if not sources:
        print("Nothing to import.")
        return

    taken = existing_identifiers(notes)
    now = dt.datetime.now()
    rows, notes_touched, warnings = [], [], []

    for path in sources:
        rel = path.relative_to(vault)
        text = path.read_text(encoding="utf-8")
        fm, body = parse_frontmatter(text)
        created = parse_created(fm, path)
        tags = [t for t in frontmatter_tags(fm) if t not in IGNORED_TAGS]

        stem_date = ISO_DATE_RE.match(path.stem)
        is_journal = bool(stem_date) or "journal" in frontmatter_tags(fm)
        date = parse_date(fm.get("date"))
        if stem_date and not date:
            date = dt.date(*(int(g) for g in stem_date.groups()))
        if is_journal and not date:
            warnings.append(f"{rel}: journal note without a usable date")
            continue

        try:
            org_body = run_pandoc(preprocess(body))
        except RuntimeError as err:
            warnings.append(f"{rel}: pandoc failed: {err}")
            continue

        copies, link_report = [], []
        target_date = date or created.date()
        year_dir = imported_dir / f"{target_date:%Y}"
        destination = year_dir / path.name

        if is_journal:
            target = find_journal(journal_dir, date)
            new_file = target is None
            ident = (unique_identifier(created, taken) if new_file
                     else re.match(r"^(\d{8}T\d{6})", target.name).group(1))
            # Everything imported lives under '* Obsidian', so the whole
            # body moves one level down and the template's '(00:16)'
            # becomes a plain time heading.
            org_body = clean_time_headings(demote(org_body))
            org_body = rewrite_links(org_body, rel.parent, vault, attach_dir,
                                     attach_link_base, ident, copies,
                                     link_report)
            if new_file:
                target = journal_dir / (f"{ident}--{date.isoformat()}"
                                        f"__journal.org")
                head = journal_front_matter(date, created, ident)
                block = obsidian_block(org_body, str(rel), now, tags, False)
                content = head + block
            else:
                current = target.read_text(encoding="utf-8")
                nested = bool(re.search(rf"(?m)^\* {OBSIDIAN_HEADING}\s*$",
                                        current))
                block = obsidian_block(org_body, str(rel), now, tags, nested)
                content = insert_into_journal(current, block, nested)
            action = "journal-new" if new_file else "journal-merge"
        else:
            ident = unique_identifier(created, taken)
            title = fm.get("title") or path.stem
            org_body = rewrite_links(org_body, rel.parent, vault, attach_dir,
                                     attach_link_base, ident, copies,
                                     link_report)
            keywords = tags or ["inbox"]
            target = inbox_silo / (f"{ident}--{slugify(title)}"
                                   f"__{'_'.join(keywords)}.org")
            content = inbox_note_text(title, created, ident, keywords,
                                      str(rel), org_body)
            action = "inbox"

        rows.append((str(rel), action, str(target), str(destination)))
        notes_touched.append(str(Path(target).expanduser().resolve()))
        for kind, detail in link_report:
            warnings.append(f"{rel}: {kind}: {detail}")

        if args.write:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            if copies:
                attach_dir.mkdir(parents=True, exist_ok=True)
            for source, dest in copies:
                if not dest.exists():
                    shutil.copy2(source, dest)
            year_dir.mkdir(parents=True, exist_ok=True)
            final = destination
            counter = 2
            while final.exists():
                final = year_dir / f"{path.stem}-{counter}{path.suffix}"
                counter += 1
            shutil.move(str(path), str(final))

    mode = "IMPORTED" if args.write else "DRY RUN - nothing written"
    lines = [f"#+title: Obsidian import {now:%Y-%m-%d %H:%M} ({mode})", "",
             "| Source | Action | Target | Moved to |",
             "|--------+--------+--------+----------|"]
    for row in rows:
        lines.append("| " + " | ".join(row) + " |")
    if warnings:
        lines += ["", "* Warnings"] + [f"- {w}" for w in warnings]
    report = "\n".join(lines) + "\n"

    print(report)
    if args.report:
        Path(args.report).expanduser().write_text(report, encoding="utf-8")
    if args.touched and args.write:
        Path(args.touched).expanduser().write_text(
            "\n".join(notes_touched) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
