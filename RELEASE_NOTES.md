# Changelog

## Unreleased — Commit review and native macOS navigation

Updated **30 September 2026**. These improvements are available on `main`.

### Review each commit

- Added a resizable commit-details pane with changed-file selection, full messages, and addition/deletion counts.
- Added native selectable unified and side-by-side code diffs with synchronised vertical scrolling.
- Added parent selection for merge comparisons and empty-tree comparison for root commits.
- Showed file renames, additions, deletions, binary files, and metadata-only changes explicitly.

### Organise the code view

- Added a compact file toolbar with previous/next change controls and a visible change counter.
- Added native path breadcrumbs with folder and file icons that keep their proportions.
- Replaced raw hunk headers with readable line ranges.
- Added fixed line-number gutters that stay out of copied text.
- Added **Wrap Lines**, remembered across launches; wrapped before/after rows remain aligned even when the panes have different widths.

### Navigate from the keyboard

- Added a **Navigate** menu with shortcuts for focusing repositories, history, changed files, and code.
- Added shortcuts for previous/next commits, files, and individual changed blocks.
- Clicking the sidebar, commit table, or changed-file list gives it keyboard focus, with native accent selection highlighting and arrow navigation.
- Moving through commits from the keyboard reveals the selected row in the history table.

### Pick up where you left off

- Remembered the last selected commit separately for each repository when switching repositories and reopening the app.
- Restored selections by commit hash when history changes; commits no longer present in history leave the selection empty.
- Guarded against older history requests and late table updates replacing the current repository's selection.
- Restored history column widths after the initial native table layout.
- Remembered changed-file pane widths and history/code divider positions across launches.

### Keep the macOS feel

- Used system backgrounds, source lists, toolbar controls, and standard AppKit splitters, with stable pane geometry as selections change.
- Adopted separate native toolbar groups on macOS 26 and later, including Golden Gate, while retaining macOS 15 support.
- Removed the sidebar toggle from the toolbar.
- Balanced the initial table columns while retaining user-resized widths.
- Moved branch, commit count, and working-tree status into the bottom bar; the window subtitle shows the repository path.
- Improved sidebar folder symbols, row spacing, path help, and add/remove accessibility labels.
- Simplified ref badges to tinted labels with semantic text colour.
- Added native **Refresh History** and ⌘R actions.
- Improved the commit sheet with a focused multiline editor, ⌘Return to commit, in-progress feedback, and inline errors.
- Added a dedicated empty-history state for repositories without commits.

### Validation and screenshots

- Added focused checks for real Git commit changes, native diff rendering and wrapping, column persistence, and repository selection memory.
- Verified repository switching and restart restoration in the live app.
- Refreshed the [README](README.md) and [screenshot gallery](Docs/Screenshots/README.md) with three captures of the running app.

## 1.1 — 24 July 2026

### Repository management

- Replaced automatic `~/Sites` discovery with an explicit native repository picker.
- Persisted added repositories and the last selected repository between launches.
- Added right-click folder colours with named swatches, a Default option, and persistent per-repository settings.
- Added clear add, remove, and sort controls to a standard macOS source-list footer.
- Renamed repository removal to “Remove from Sidebar” to make it clear that files are never deleted.

### macOS experience

- Restored the File menu with **Add Repository…** and the standard `⌘O` shortcut.
- Added Delete-key support for removing the selected repository from the sidebar.
- Simplified toolbar status text to natural labels such as “Clean” and correctly pluralised commit and change counts.
- Improved VoiceOver output for repository colours and clarified control help text.

### Performance

- Stopped rescanning every saved repository during the ten-second history refresh.
- Full repository metadata is refreshed when the app becomes active; background polling now checks only the selected repository.
