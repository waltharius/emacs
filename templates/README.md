# Note Templates

This directory contains templates for different types of notes.

## Available Templates

### `project.org` - Project Management Template
Standard structure for project tracking with Org-agenda and Kanban integration.

**Placeholders:**
- `{{TITLE}}` - Project name
- `{{DATE}}` - Current date (YYYY-MM-DD)
- `{{DATETIME}}` - Full timestamp ([YYYY-MM-DD Www HH:MM])
- `{{CATEGORY}}` - Sanitized project name
- `{{DEADLINE}}` - Default deadline (7 days from creation)

**Usage:** `C-c n p` (my/denote-create-project)

**Standards:**
- 3 phases minimum (Planning, Execution, Review)
- TODO states: TODO → NEXT → INPROGRESS → DONE
- Time tracking with Effort estimates
- Kanban board for visual overview
- Clock table for time summary

### `journal.org` - Daily Journal Template (TODO)
### `meeting.org` - Meeting Notes Template (TODO)
### `zettelkasten.org` - Zettelkasten Note Template (TODO)

## Creating Custom Templates

1. Create `.org` file in this directory
2. Use `{{PLACEHOLDER}}` syntax for dynamic content
3. Add to `my/load-template` function if needed
4. Document placeholders in this README

## Modifying Templates

Templates can be edited directly - changes take effect immediately.
No need to reload Emacs or recompile code.

## Version History

- v1.0 (2025-10-09): Initial project template with standards documentation
