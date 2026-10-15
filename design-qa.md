# Uncommitted changes — option 1

Date: 15 October 2026

final result: passed

## Evidence and state

- Source visual: the first displayed mockup selected by the user during the 15 October design review (working-tree row above history). The exploratory mockup remains in that review conversation and is not a bundled app asset.
- Implementation: `dist/Don Git 2.app`, built from this repository and running against the actual Don Git 2 repository.
- Implementation screenshot evidence: inline CUA captures in this conversation, including the final source/implementation comparison. The capture API returned image buffers, without a filesystem screenshot path; no saved screenshot file is claimed.
- Source: 1613 × 975 pixels at approximately 1× UI density. Implementation: 3228 × 1998 pixels, corresponding to a 1614 × 999 point native window at 2× density. Comparison used corresponding logical sizes, without stretching images. The 24-point window-height difference and previously saved splitter positions were treated as existing window preferences, not design defects.
- State compared: dark appearance, Uncommitted Changes selected, a Swift file selected, side-by-side HEAD / Working Copy diff visible. Both images were emitted together in the same comparison input. The source contains three example files; the implementation uses the actual changed files and counts.
- Additional state: normal saved system/light appearance, unified and side-by-side diff modes, and keyboard movement between uncommitted changes and actual commits.

## Findings and comparison history

- Resolved P2: history focus could remain in the changed-file list after Command-1. Added native first-responder handling for the history table and avoided reassigning unchanged history/file selections during refresh. After rebuilding, Command-1 followed by Down selected the real HEAD commit; Up returned to Uncommitted Changes. The final combined visual capture shows the working-tree row with the active native blue selection.
- No remaining actionable P0/P1/P2 visual findings. The hollow working-tree node, dashed connection to HEAD when HEAD is the first history row, file count, Not committed label, real commit badges, lower changed-file list, and HEAD / Working Copy comparison match the selected layout.
- Intentional platform adaptations: existing system typography, native segmented controls, existing diff renderer, adaptive macOS material/tint, saved column and splitter sizes, and inactive selection colors remain native. Only the focused pane receives the active selection highlight. A working-tree node is not connected to an unrelated remote commit when another branch appears above HEAD.

## Required fidelity surfaces

- Fonts and typography: existing system UI font and monospaced native diff text retained; title, secondary description, file count, and code line-number hierarchy remain readable.
- Spacing and layout: repository sidebar, history above details, file list beside code, thin separators, and bottom status bar retained. Persistent controls remain visible; long file lists and code scroll within their panes. Existing user-resized panes remain adjustable.
- Colors and tokens: native active/inactive selection, semantic red/green diff colors, system backgrounds, and existing folder/ref colors work in both dark and light appearances.
- Asset fidelity: standard system file/folder icons and the existing native graph renderer are reused. The working-tree node is a hollow native drawing, not a rasterized interface or fake commit.
- Copy and content: Uncommitted Changes, Not committed, Compared with HEAD, Updates as you edit, HEAD, and Working Copy appear in the appropriate locations. Empty repositories use Empty tree. Actual file names and totals replace mock data.
- Focused inspection: row title/subtitle, hollow node/stem, selected file, diff headers, and line gutters were readable in the combined full-resolution input; separate crop images were not needed to assess those details.

## Verification

- Packaged app builds and launches successfully.
- Local-change checks pass for staged/unstaged edits, new and ignored files, empty/binary files, symlinks, unusual/literal paths, renames, deletions, recreated paths, unchanged contents with dirty stat data, conflicts, and repositories before their first commit.
- Tests verify that inspection preserves the actual index byte-for-byte and leaves HEAD unchanged. Committing is tested only in disposable fixture repositories.
- Same-file edits update even when the status and file count stay the same; unchanged refreshes preserve file/change selection. After committing, the synthetic row disappears and the actual new HEAD is selected.
- Existing commit-change, repository-selection, native diff rendering/wrapping, column persistence, and nine graph checks pass. Origin-refresh regression checks also pass; origin status is visible in the running app.
- Native UI checks cover repository selection, working-tree selection, file selection, HEAD/working-copy headings, both diff presentations, Command-1 focus, arrow-key traversal, restart restoration, and both light and dark appearances.

## Implementation checklist

- [x] Real local data in the selected layout.
- [x] Independent local polling and remote fetches.
- [x] Read-only inspection and stable selection.
- [x] Build, focused regression checks, and native visual/interaction review.
- [x] Leave the finished native app open for inspection.

No follow-up polish is required for the requested feature. Browser console checks are not applicable to this native Swift/AppKit application.
