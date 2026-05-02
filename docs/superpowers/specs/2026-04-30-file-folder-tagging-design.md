# File & Folder Tagging — Design

## Goal

Add Finder-compatible file and folder tagging to BetterFinder. Tags are stored using the macOS system mechanism (`URLResourceKey.tagNamesKey`, backed by the `com.apple.metadata:_kMDItemUserTags` extended attribute), so tags written by BetterFinder appear in Finder and vice versa.

## Scope

This first pass covers four user-facing surfaces:

- **A.** Color dots next to filenames in the file list.
- **C.** Right-click context menu with a row of toggleable color dots and a "Tags…" item that opens a token-field popover.
- **D.** Tag editor in the Info widget for the current selection.
- **E.** Sidebar entries (one per favorite tag) that open a flat virtual folder showing all files with that tag, queried via Spotlight.

Out of scope for this pass: Tags column in list view, filter-by-tag in the toolbar, in-app tag management UI (rename/delete/recolor), drag-and-drop onto sidebar tags. These are deferred to follow-up specs.

## Tag catalog source

The list of available tags, their colors, and the favorite-for-sidebar ordering is read from Finder's preferences (`com.apple.finder` defaults), not maintained independently. Users continue to manage tags in Finder Settings → Tags. BetterFinder is a read-only consumer of that catalog.

Keys read (stable but undocumented; in use by Finder since macOS 10.9):

- `FavoriteTagNames` — array of strings, ordered. Empty strings act as section separators in Finder; we treat them the same way (separator in our sidebar).
- `Tags` — array of dicts; each dict has at least `n` (name, String) and `l` (color index, Int 0–7).

If parsing either key fails, fall back to a hardcoded default catalog of the seven Finder color tags (Red, Orange, Yellow, Green, Blue, Purple, Gray) so the app remains functional. We never write back to `com.apple.finder` defaults.

If a user assigns a tag whose name isn't in the catalog (typed a new name into the picker), `TagService` adds it to its in-memory catalog with color `.none`. On the next reload from Finder prefs, if the user has since configured a color in Finder, our copy updates.

The catalog is reloaded:

- At app launch.
- On `NSApplication.didBecomeActiveNotification` (catches changes the user made in Finder while we were backgrounded).

## Architecture

### New files

- `Models/FileTag.swift` — value type:

  ```swift
  struct FileTag: Hashable, Identifiable {
      var id: String { name }
      let name: String
      let color: TagColor
  }

  enum TagColor: Int, CaseIterable {
      case none = 0, gray, green, purple, blue, yellow, red, orange
  }
  ```

  `TagColor` mirrors Finder's color index. A `swiftUIColor: Color` computed property maps each case to a hue tuned to match Finder's actual rendering.

- `Services/TagService.swift` — single source of truth for tag I/O.

  - `@Observable` properties:
    - `availableTags: [FileTag]` — full catalog.
    - `favoriteTags: [FileTag?]` — sidebar favorites in order, with `nil` entries for separators.
  - Public methods:
    - `setTags(_ tags: [FileTag], on urls: [URL]) throws` — writes via `URLResourceValues.tagNames`. On any per-URL failure (permission denied, non-local volume), throws a `TagWriteError` containing per-URL success/failure results so the caller can update in-memory state for the URLs that did succeed.
    - `tags(for url: URL) -> [FileTag]` — reads via `URLResourceKey.tagNamesKey`, mapped through the catalog.
    - `toggle(_ tag: FileTag, on urls: [URL])` — adds the tag to all URLs that don't have it; if every URL has it, removes it from all.
  - Private:
    - `loadCatalog()` — parses `com.apple.finder` defaults.
    - Catalog refresh on `didBecomeActiveNotification`.

- `Services/TagQueryService.swift` — wraps `NSMetadataQuery` for "all files with tag X". One query instance per active tag-results view.

  - Predicate: `NSPredicate(format: "%K == %@", "kMDItemUserTags", tag.name)`. NSMetadataQuery handles the multi-value array match natively.
  - Search scopes: `[NSMetadataQueryLocalComputerScope, NSMetadataQueryUserHomeScope]`.
  - Subscribes to `.NSMetadataQueryDidFinishGathering` and `.NSMetadataQueryDidUpdate`. On each, materializes results into `[FileItem]` (reusing `FileSystemService` to build `FileItem`s from URLs) and calls a delegate / closure on the main actor.
  - `stop()` disables updates and stops the query.

- `Views/FileList/TagDotsView.swift` — small SwiftUI view rendering up to 3 trailing color circles. See "UI components" below.

- `Views/Tags/TagPickerPopover.swift` — token-field popover. See "UI components" below.

- `Views/Tags/TagPickerTokenField.swift` — `NSViewRepresentable` wrapper around `NSTokenField` with autocomplete and per-token color rendering. Used both standalone (Info widget, inline) and inside `TagPickerPopover`.

### Changes to existing files

- `Models/FileItem.swift` — add stored property `let tags: [FileTag]` (default `[]`). Update `==` to include tags so the list view re-renders when a file's tags change.
- `Services/FileSystemService.swift` — add `.tagNamesKey` to the resource keys requested when listing a directory and when building a single `FileItem`. Map raw tag names through `TagService` to produce `[FileTag]`.
- `ViewModels/FileListViewModel.swift` — add:

  ```swift
  enum Mode {
      case directory(URL)
      case tagQuery(FileTag)
  }
  var mode: Mode
  func openTagQuery(_ tag: FileTag)
  ```

  In `tagQuery` mode, `items` is populated by `TagQueryService` instead of `FileSystemService`. Sort/search filtering is reused unchanged. Directory monitoring is paused; tag-query updates come from `NSMetadataQuery`.

- `Views/Sidebar/SidebarView.swift` — new `Section(header: Text("Tags"))` after Locations. Rows render colored dot + tag name; tag = virtual URL `tag:///<percent-encoded-name>`.
- `ContentView.swift` — when sidebar selection changes, branch on URL scheme: `tag://` → `viewModel.openTagQuery(...)`; everything else → existing `viewModel.navigate(to:)`.
- `Views/FileList/FileRowView.swift` — append `TagDotsView(tags: fileItem.tags)` to the Name column trailing edge.
- `Views/FileList/FileListView.swift` — add the colored-dot row + "Tags…" item to the per-item context menu. The empty-space (background) context menu does not gain these items. Path bar updates to render the tag-mode segment when `mode == .tagQuery(...)`.
- `Views/Widgets/InfoWidgetView.swift` — add a "Tags" row showing inline `TagPickerTokenField` for the current selection.

## Data flow

### Read path (folder navigation)

1. User navigates to a folder. `FileListViewModel` calls `FileSystemService.listDirectory(url)`.
2. `FileSystemService` requests resource values including `.tagNamesKey` for each entry.
3. Raw `[String]` tag names are resolved via `TagService.resolve(names:)` → `[FileTag]`.
4. Each `FileItem` carries its `tags` array.
5. `FileRowView` renders `TagDotsView` if `tags` is non-empty.

### Read path (tag virtual folder)

1. User clicks a sidebar tag. `ContentView` decodes `tag:///<name>`, looks up `FileTag` in catalog, calls `viewModel.openTagQuery(tag)`.
2. `FileListViewModel` sets `mode = .tagQuery(tag)`, clears `items`, starts `TagQueryService`.
3. `TagQueryService` runs `NSMetadataQuery`. On `DidFinishGathering` and each `DidUpdate`, results are materialized into `[FileItem]` and pushed back.
4. View renders flat list. Path bar shows "Tag: <name>" with a colored dot.

### Write path

1. User invokes a tag operation (dot click in context menu, popover edit, Info widget edit).
2. Caller calls `TagService.setTags(_:on:)` or `TagService.toggle(_:on:)`.
3. `TagService` writes via `URLResourceValues.tagNames` for each URL.
4. On success, `FileListViewModel` refreshes the affected `FileItem`s (re-reads resource values for those URLs and updates `items` in place — no full directory reload).
5. If a tag-query view is currently visible for the affected tag, `NSMetadataQuery` will deliver an update that resets the result set.

### Reactivity to external changes

- **Tag changes from Finder while we're viewing the folder:** the existing directory monitor (`DispatchSourceFileSystemObject`) does not fire on extended-attribute changes. Add an FSEvents stream watching the visible directory with `kFSEventStreamCreateFlagWatchRoot` and check `kFSEventStreamEventFlagItemXattrMod` on the file flags. On each event, refresh that single file's `FileItem` rather than the whole directory.
- **Catalog changes from Finder Settings:** reloaded on `didBecomeActiveNotification`. Sidebar rows update via `@Observable`.

## UI components

### `TagDotsView` — file row color dots

- Renders up to 3 circles. Each: 8pt diameter, fill = `tag.color.swiftUIColor`, 0.5pt border `Color.primary.opacity(0.15)`.
- Circles overlap by 1pt (drawn back-to-front, last tag on top).
- Hidden entirely (no view emitted) when `tags.isEmpty`. No layout space reserved.
- Container has `.help(tags.map(\.name).joined(separator: ", "))` for hover tooltip.
- For `TagColor.none`, renders as a hollow gray ring (stroke only).

### Right-click context menu

The per-item file context menu gains two elements at the top, above existing items:

1. **Color dot row** — `HStack` of clickable color dots, one per favorite tag. Each click toggles the tag on the currently right-clicked item (or full selection if the right-clicked item is part of the selection — same rule as other menu actions). Currently-applied tags get a thin `Color.primary` ring around the dot to indicate active state.
2. **"Tags…" item** — opens `TagPickerPopover` anchored to the row.

**SwiftUI implementation note:** SwiftUI's `Menu` does not natively support a horizontal row of custom controls inside a context menu. We will first attempt a SwiftUI-only approach using a single menu item with a custom `HStack` label. If that proves visually broken or unclickable per-dot, we fall back to building this section as an `NSHostingView` embedded in an `NSMenuItem`, attached via an `NSMenu` extension or a small `NSViewRepresentable` host. The fallback is acceptable; the project already drops to AppKit elsewhere (see `TerminalLauncherService`).

### `TagPickerPopover` and `TagPickerTokenField`

Token-field UI for free-form tag editing.

- Built on `NSTokenField` via `NSViewRepresentable` — SwiftUI has no native token field that supports per-token coloring.
- Each token = colored dot + tag name.
- Autocomplete sources from `TagService.availableTags`.
- Typing an unknown name + Return creates a new in-memory tag (catalog gets a transient entry with color `.none`).
- Backspace at end-of-field removes the trailing token.
- For multi-selection state:
  - Tags applied to **all** selected files render as solid tokens.
  - Tags applied to **some** selected files render dimmed (50% opacity) with a "—" affordance instead of "×". Removing a dimmed token removes it from the files that have it. Adding a brand-new token adds it to all selected files.
- On commit, computes the diff against each file's prior tags and calls `TagService.setTags` for the affected URLs.

`TagPickerPopover` wraps `TagPickerTokenField` in a `Popover` with an OK / done button. The Info widget uses `TagPickerTokenField` directly inline (no popover).

### Info widget

`InfoWidgetView` currently shows kind/size/modified/etc. for the active selection. Add a "Tags" row that:

- Hidden when selection is empty.
- For single or multiple selection: renders inline `TagPickerTokenField`.
- Edits commit on token-field commit (Return, blur, or token change), via the same `TagService.setTags` path.

### Sidebar Tags section

- New `Section(header: Text("Tags").fontWeight(.bold))` placed after Locations.
- Rows iterate `viewModel.favoriteTags` (provided by `TagService`). Empty entries (separators in Finder) render as a thin divider line.
- Each row: `Label` with a colored circle as the icon (custom view, not an SF Symbol) and the tag name.
- Tag URL: `URL(string: "tag:///\(name.addingPercentEncoding(...))")`. The host is empty; the path carries the name.
- No drag destination in this scope.

## Tag query (sidebar virtual folder)

When `FileListViewModel.mode == .tagQuery(tag)`:

- The pane's `TagQueryService` is started for `tag`.
- Path bar renders a single non-navigable segment: colored dot + "Tag: \(tag.name)".
- Toolbar Back/Forward continues to work between recent locations (a tag query counts as a location entry in the navigation history).
- Sort and search filters apply in-memory to the result set, identical to directory mode.
- Double-clicking a folder in tag results transitions `mode` back to `.directory(folderURL)` and the query stops.
- Double-clicking a file opens it via the existing handler.
- Selection, multi-select, context menu, and tag editing all work normally.
- Status bar reads "N items" as usual.

## Edge cases & error handling

- **Network / non-local volumes:** `URLResourceKey.tagNamesKey` is local-only. `TagService.setTags` checks `URLResourceValues.volumeIsLocal` for each URL; for non-local URLs, surfaces "Tags can't be applied to files on this volume." via `FileListViewModel.errorMessage` and skips the write. Reads on non-local URLs return `[]` cleanly.
- **Read-only mount or permission denied:** `setResourceValues` throws; caught and surfaced via `errorMessage`. In-memory `FileItem.tags` is not mutated on failure.
- **Tag with special characters in name:** virtual URL encodes via `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`. `ContentView` decodes via `URLComponents`.
- **Tag deleted in Finder while shown in BetterFinder sidebar:** on next catalog refresh, the row disappears. If the user is currently viewing that tag's virtual folder, fall back to "Tag no longer exists" empty state and stop the query. Forward/Back history entries pointing to deleted tags become non-functional and show the same empty state if revisited.
- **Catalog parse failure:** fall back to default 7-color catalog; log once.
- **Empty tag query result:** "No files tagged \(tag.name)." centered.
- **Spotlight not indexing a volume:** files on that volume won't appear. We don't try to fall back to a manual scan — Spotlight is the only realistic enumeration path. Documented behavior.
- **`NSMetadataQuery` fails to start (sandbox/permission):** error banner via `errorMessage`.
- **Performance — file row dots:** `TagDotsView` returns `EmptyView` when `tags.isEmpty`. No per-row allocation when nothing is tagged.

## Testing

The project has no automated test suite (per CLAUDE.md). The implementation plan will include a manual verification checklist:

- Apply / remove tags via context menu dot row → dot indicator updates in place; tag visible in Finder.
- Apply / remove tags via "Tags…" popover → same.
- Apply / remove tags via Info widget token field → same.
- Multi-selection tag operations → mixed-state tokens render correctly; toggling adds-then-removes correctly.
- Sidebar tag click → flat virtual folder shows expected files; live updates as files are tagged/untagged from another window.
- Tag a file in Finder while BetterFinder is open and showing that file's folder → dot indicator updates within ~2 seconds.
- Apply tag to file on read-only or network volume → error message surfaces; no crash.
- Tag picker with tag whose name contains spaces, slashes, unicode → round-trips correctly through sidebar URL.
- Empty tag virtual folder → empty-state text shown.
