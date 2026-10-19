# Inline worktree labels — option 1

Date: 19 October 2026

final result: passed

## Latest refinement: adaptive native branch pills

- Supersedes the solid-fill colour option below at the user's request. Removed custom RGB fills and forced white text. Branch badges use macOS systemGreen/systemRed with semantic primary text, medium-weight system caption text, and a subtle thin outline.
- Light appearance uses 12% tint and 25% outline opacity; dark appearance uses 22% tint and 35% outline opacity. Increased Contrast strengthens the outline to 60%. House/folder icons, pill dimensions, branch pairs, tooltips and graph rendering are unchanged.
- Native WTC captures: `/tmp/dongit-native-pills-light.png` and `/tmp/dongit-native-pills-dark.png`, both 3228 × 1998 pixels at 2× (1614 × 999 points). Both appearances were inspected in the running app: readable dark/light foregrounds, muted colour separation and aligned inline icons. Existing selected/inactive row treatments remain native. Original Light preference restored and app left on WTC.
- Packaged build and whitespace checks pass. No new logic tests were added for this presentation-only refinement. No actionable layout or readability issues were observed.

## Previous refinement: brighter branch pills, colour option 1

- Selected colour reference: `/Users/alexfraser/.codex/generated_images/01a15390-63ca-7a73-875a-6abbf6810f0d/exec-19286b04-92d8-4c07-af27-101db84234df.png` (first displayed colour mockup).
- Applied rich green local fills, rich red remote fills, white text/icons and stronger thin outlines. Other badge types retain their existing treatment. Pairing, icon placement, graph colours, diff colours and row selection behavior are unchanged.
- Implementation screenshot: `/tmp/dongit-rich-branch-pills.png`, 3228 × 1998 pixels at 2×, corresponding to 1614 × 999 points. Source is 1594 × 987 pixels at approximately 1×. Source and implementation were opened together in one comparison input, comparing their corresponding logical dimensions. WTC, dark appearance, c246920 selected and Side by Side diff match the selected mockup state. Existing window chrome/material and native rendering remain intentional differences.
- Font, capsule size, spacing, copy, paired ordering and system house icon match the existing native design. Full-view feature text is legible; no separate crop was needed. Green is slightly darker than the generated sample to keep white small-label contrast at 4.57:1; red contrast is 5.78:1. Fixed fill colours keep those contrasts in either appearance. No new image assets or UI controls were introduced.
- Packaged build and whitespace checks pass. Native selection and commit details were checked after restarting. First matched-state comparison passed, with no P0/P1/P2 findings or visual repair iterations. App left open on WTC. Colour changes remain uncommitted.

## Previous refinement: matching checkout icons

- Both checkout types now use the same compact icon placement inside the local branch capsule: house for the main checkout, folder for linked worktrees. Removed the Worktree text while retaining the native tooltip and accessible checkout type/path. Both icons use the same system font, padding and semantic color. No data, pairing or graph behavior changed.

## Previous refinement: compact main checkout marker

- Replaced the separate grey Main checkout capsule with the native SF Symbols house icon inside the local branch capsule, as requested. Existing hover text and accessibility descriptions still identify Main checkout and its full path.
- Packaged build and whitespace checks pass. Native CUA screenshot review on avail-admin confirms the house beside dev, directly followed by origin/dev; main/origin-main remains a separate pair. Existing repository, selected commit, appearance and diff presentation were retained. Earlier comparisons below document the previous label treatment.

## Follow-up: HEAD connection and branch pairs

- User-approved follow-up on 19 October 2026: restore the dotted connection to actual HEAD even below other branch tips, and group local/remote pills into logical pairs.
- Implemented an independent dotted lane past intervening commits, with a curved join to HEAD and no extension below it. Direct HEAD, detached HEAD and missing/unborn HEAD have explicit handling. Both graph cell types use the same vertical bleed to bridge native row spacing.
- Presentation groups the current local branch first, then other locals with their exact matching remote refs (origin first). Checkout labels remain with their local pill. Tags, symbolic remote HEAD and unpaired refs remain separate. Git's original ref metadata and graph routing remain intact.
- Native WTC screenshot: `/tmp/dongit-head-connection-and-ref-pairs.png`, 3228 × 1998 pixels at 2× density. The dotted line visibly bypasses the Tesla commit and joins dev's HEAD, with dev/origin-dev and main/origin-main pairs. Verified with both a saved commit and Uncommitted Changes selected in the existing System/light appearance; app left open on WTC.
- Build, all 11 graph checks, parent topology across WTC's 1,932 commits, worktree lifecycle regression checks and whitespace checks pass. New tests cover direct/lower/detached/missing HEAD, multiple bypassed commits, clean history, exact remote matching, slashed branch names, custom remotes, checkout metadata preservation and unpaired refs. No actionable visual issues remain.

## Visual evidence

- Selected visual: `/Users/alexfraser/.codex/generated_images/01a15390-63ca-7a73-875a-6abbf6810f0d/exec-4282bbe0-2ecd-4579-9fa4-60d19f849f29.png`, the first displayed mockup (inline folder icon and Worktree label).
- Running implementation: `dist/Don Git 2.app`. Screenshot: `/tmp/dongit-inline-worktree-dark.png`. Source and implementation were emitted together in one CUA comparison input.
- Source is 1613 × 975 pixels at approximately 1× density; implementation is 3228 × 1998 pixels, a 1614 × 999 point native window at 2×. Comparison uses corresponding logical sizes without stretching. The existing saved column widths, splitter positions, 24-point height difference, native material tint and current system font remain intentional platform adaptations.
- Matched feature state: dark appearance, linked Tesla branch selected, inline Worktree label, separate Main checkout label, unified diff below. A disposable WTC Preview repository supplies real Git checkout records. Actual WTC no longer has the Tesla worktree, so its correct live state shows only dev's Main checkout label. WTC's checkouts were not changed for the preview.
- Light appearance was also inspected. Original System appearance and Side by Side presentation were restored. Temporary preview was removed from the sidebar; app left open on WTC with its prior commit selection retained.

## Findings and fidelity

- No actionable P0/P1/P2 differences. The folder symbol and Worktree text are inside the local branch capsule; Main checkout is an adjacent subdued capsule. Remote refs and other local branches remain unmarked, including when they point at the same commit.
- Fonts/typography: existing system caption size and semibold badge weight retained; both labels are legible and aligned with existing refs. Native accessibility labels include branch, checkout type and full path.
- Spacing/layout: existing table columns and row heights remain unchanged. The new icon/text uses compact spacing within the capsule. Existing native truncation and user-resized column behavior are retained. Full-resolution feature rows were readable in the combined comparison; no separate crop was necessary.
- Colors/tokens: existing green local and red remote tints, semantic secondary text, native blue selection and adaptive system materials retained in light and dark appearances.
- Assets: native SF Symbols folder icon; no rasterized UI, custom image assets or new icon system.
- Copy/content: Worktree and Main checkout match the selected concept. Native help contains the checkout path. Automated tooltip-hover capture was not performed; help and accessibility descriptions are defined on each badge.
- Comparison history: first combined comparison passed; no visual corrections were needed. Test-fixture path expectations were corrected for macOS's /var and /private/var aliases before the integration checks passed.

## Verification

- Packaged app build passes.
- Worktree integration checks pass: NUL-safe paths with spaces/newlines/quotes, locked checkouts, detached/bare/prunable entries, exact local-branch matching, tag collisions and custom remotes, linked-repository perspective, addition, branch switch, move, removal, stale folders, selection preservation, and main checkout branch switches without a commit change.
- Live read-only check of WTC reports dev as Main checkout.
- Existing nine graph checks, repository-selection checks and origin-refresh checks pass.
- Native UI verification covers linked branch selection, commit details, both diff modes, light/dark readability and restored preferences. Browser console checks do not apply to this SwiftUI/AppKit app.

No follow-up polish is required for this feature.

---

# Previous verification: uncommitted changes — option 1

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
