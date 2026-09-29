# Don Git 2

Don Git 2 is a native macOS Git history viewer for local repositories. It uses SwiftUI and standard macOS controls to keep repository navigation, commit history, branches, refs, and local changes visible in one window.

![Don Git 2 showing colour-coded repositories and commit history](Docs/Screenshots/repository-history.png)

## Features

- Add individual Git repositories with the sidebar `+` button or **File → Add Repository…** (`⌘O`).
- Keep added repositories and the last selection between app launches.
- Assign a persistent colour to each repository folder from its right-click menu.
- Sort repositories by name or most recent commit date.
- View all branches and refs in a topological commit graph.
- Select a commit to inspect its changed files, full message, and addition/deletion counts.
- Read selectable code diffs in unified or aligned side-by-side mode, with synchronised vertical scrolling.
- Compare merge commits against either parent; view root commits against an empty tree.
- See the current branch, commit count, and working-tree status in the bottom status bar.
- Refresh history with the native toolbar action or **File → Refresh History** (`⌘R`).
- Stage and commit all local changes with a multiline commit message (`⌘Return` in the commit sheet).

The repository picker uses the standard macOS open panel and accepts any folder inside a Git working tree.

Use the **Navigate** menu to move through history and changes from the keyboard:

| Action | Shortcut |
| --- | --- |
| Focus repositories / history / changed files / code | ⌘0 / ⌘1 / ⌘2 / ⌘3 |
| Previous / next commit | ⌃⌘↑ / ⌃⌘↓ |
| Previous / next changed file | ⌥⌘↑ / ⌥⌘↓ |
| Previous / next changed block | ⌥⌘← / ⌥⌘→ |

Click the repository sidebar, commit table, or changed-file list to focus it: the selected row uses the native accent highlight and arrow keys move through its rows. Code supports native text selection and copying. File names, renames, binary files, and file metadata changes are shown explicitly.

## Requirements

- macOS 15 or later
- Swift 6.1 or later

## Build and run

```bash
./script/build_and_run.sh
```

To compile without creating and launching the app bundle:

```bash
swift build
```

The packaged app is written to `dist/Don Git 2.app`.

To package without launching, use `./script/build_and_run.sh --build`.

Run the focused checks with `bash script/test_changes.sh`, `bash script/test_diff_view.sh`, `bash script/test_graph.sh`, and `bash script/test_columns.sh`.

## Release notes

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the latest changes.
