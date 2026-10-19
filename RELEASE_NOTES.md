# Changelog

## 19 October 2026 — Checkout markers and clearer branch history

### Identify checkouts

- Show a house icon inside the local branch pill for the main checkout and a folder icon for linked worktrees.
- Show the checkout type and full folder path on hover and through accessibility descriptions.
- Refresh checkout markers when worktrees are added, moved, removed or switched to another branch, including switches at the same commit.
- Keep detached, bare and stale worktree records from producing misleading branch markers.

### Read branch relationships

- Group each local branch with its matching origin pill, with the current branch first. Tags, symbolic remote HEAD and unmatched refs remain separate.
- Connect Uncommitted Changes to its actual HEAD with a dotted line, using a separate lane past newer commits on other branches.
- Use macOS system green and red, subtle appearance-aware tints, semantic text colours and lighter outlines. Pills adapt to light, dark and increased-contrast appearances.

### Validation

- Added real-Git worktree lifecycle checks, including unusual paths, custom remotes, colliding tag names, linked-repository views and cached refreshes.
- Expanded graph checks to cover dotted HEAD connections and branch pairing; verified parent connections across WTC's 1,932 commits.
- Built the packaged app and checked the final native styling in both light and dark appearances.

## 15 October 2026 — Origin refresh and uncommitted changes

### Review uncommitted changes

- Added an **Uncommitted Changes** row above commit history with a hollow node, file count, and **Not committed** label.
- Reused the changed-file list, unified and side-by-side diffs, wrapping, and change navigation for current working-copy changes against HEAD.
- Included staged and unstaged edits, new files, deleted and renamed files, binary files, and merge conflicts; ignored files remain excluded.
- Explained staged edits whose working copy already matches HEAD instead of hiding them.
- Refreshed local changes every three seconds independently of network fetches, preserving file and unchanged diff selections.
- Supported repositories before their first commit and selected the new HEAD after committing reviewed changes.
- Disabled Git's optional index writes and automatic diff index refresh during inspection; verified the real index remains byte-for-byte unchanged.
- Added native history focus handling and focused local-change checks for index preservation, unusual paths, phantom stat changes, staging, live edits, committing, and conflicts.

### Keep origin branches current

- Fetch origin on repository selection, app activation, manual refresh, and every minute, independently of local history checks.
- Show fetch progress, the last successful origin check, missing origin, and failures in the bottom bar without hiding local history.
- Update remote markers for new branches, deleted branches, and force-pushes without changing local branches or files.
- Keep background checks noninteractive, bound fetches to 30 seconds, and share overlapping requests for the same repository.
- Show fetched remote history even when the local repository has no commits yet.

### Validation

- Added `script/test_local_changes.sh` and `script/test_origin_refresh.sh` with disposable Git repositories for real file changes, remote advances, force-pushes, branch deletions, overlapping requests, and connection failures.
- Passed the packaged app build and checks for local changes, origin refresh, commit changes, repository selection, native diff rendering, column persistence, and graph topology.
- Verified the selected layout, native history keyboard focus, and unified/side-by-side local diffs in the running app in light and dark appearances. See [design QA](design-qa.md) for the review record.

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

- Matched the routing and commit order of `git log --graph --oneline --decorate --all` using a single history walk for graph, commit details, and decorations.
- Carried Git's lane colours through commit dots and translated ordinary and bright ANSI hues into adaptive macOS colours with measured contrast in light, dark, and increased-contrast appearances.
- Added curved joins, outlined merge nodes, complete multi-parent merge stems, and separate paths at crossings and long horizontal connectors.
- Kept the Graph column resizable, with an ellipsis for lanes beyond its current width.
- Fixed disconnected branch lines when Git collapses a lane across consecutive commit and routing rows.
- Added **System**, **Light**, and **Dark** appearance choices in the native Settings window, applied immediately and remembered across launches.
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

- Added tests that trace the actual drawing segments to parent hashes, including three 48-commit interleaved histories and a four-parent merge. Verified all rendered parent connections in WTC, avail-admin, and Don Git 2.
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
