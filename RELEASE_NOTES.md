# Release Notes

## Unreleased — macOS visual polish

- Adopted the system window background and separate native toolbar groups on macOS 26 and later, including Golden Gate, while retaining macOS 15 support.
- Removed the sidebar toggle from the toolbar.
- Balanced the default table columns for the initial window size, retaining user-resized widths.
- Moved branch, commit count, and working-tree status into a quiet bottom bar; the window subtitle shows the repository path.
- Improved sidebar folder symbols, row spacing, path help, and add/remove accessibility labels.
- Simplified ref badges to tinted content labels with semantic text colour for contrast, without glass or shadows.
- Added a native Refresh History action and ⌘R shortcut.
- Improved the commit sheet with a focused multiline text editor, ⌘Return to commit, in-progress feedback, and inline errors.
- Added a dedicated empty-history state for repositories with no commits.

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
