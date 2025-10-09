# Project Menu Reference (C-c p)

## Structure

This document serves as reference for the Transient menu defined in
`13-project-management.el`. Modify the code there based on this structure.

## Layout (4 columns)

### Column 1: Project Management

#### Create & Open
- `n` - New project (my/denote-create-project)
- `o` - Open project (my/open-project-file)
- `x` - Find by property (my/denote-find-by-property)

#### Statistics
- `%` - Completion % (my/org-project-completion-percentage)
- `t` - Time summary (my/org-time-summary)
- `m` - Update modified (my/org-update-modified-property)

#### Agenda Views
- `a` - Agenda dispatch (org-agenda)
- `p` - All projects (org-agenda nil "p")
- `d` - Daily (org-agenda nil "d")
- `w` - Weekly review (org-agenda nil "w")

#### Kanban & Reports
- `k` - Kanban board (org-kanban/initialize)
- `K` - Shift task (org-kanban/shift)
- `R` - Clock report (org-clock-report)
- `C` - Columns view (org-columns)

### Column 2: Time Tracking

#### Clock
- `i` - Clock in (org-clock-in)
- `c` - Clock out (org-clock-out)
- `j` - Goto clocked (org-clock-goto)
- `l` - Clock last (org-clock-in-last)

#### Effort & History
- `e` - Set effort (org-set-effort)
- `E` - Modify effort (org-modify-effort-estimate)
- `h` - Show history (org-clock-display)
- `H` - Hide history (org-clock-remove-overlays)

### Column 3: Task Management

#### TODO & Priority
- `s` - Set TODO (org-todo)
- `S` - Todo cycle (org-shiftright)
- `,` - Set priority (org-priority)
- `.` - Priority up (org-priority-up)
- `/` - Priority down (org-priority-down)

#### Schedule & Deadline
- `z` - Schedule (org-schedule)
- `Z` - Deadline (org-deadline)
- `T` - Set tags (org-set-tags-command)
- `P` - Set property (org-set-property)

### Column 4: Navigation
- `q` - Quit (transient-quit-one)
- `?` - Help (describe-mode)

## Adding New Commands

1. Edit `13-project-management.el`
2. Find `transient-define-prefix my/project-transient-menu`
3. Add new binding in appropriate column/group
4. Update this reference file
5. Test with `C-c p`

## Design Principles

- **No icons** - save space, faster rendering
- **Logical grouping** - related commands together
- **Short labels** - max 15 characters
- **Mnemonic keys** - intuitive letters (n=new, o=open, etc.)
- **Consistent layout** - same structure every time
