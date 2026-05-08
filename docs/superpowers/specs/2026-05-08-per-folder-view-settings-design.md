# Per-Folder View Settings — Design

## Problem

BetterFinder currently has partial, inconsistent per-folder memory of view preferences:

- `sortCriteria` and `showHiddenFiles` are persisted per folder via two static dicts on `FileListViewModel` (`folderSortOrders`, `folderShowHiddenFiles`), each backed by its own `UserDefaults` key. Both follow the rule "store only when the user deviates from the app default."
- `viewMode` (list vs. thumbnails) is **not** persisted at all. It's a per-pane value that defaults to `.list` and resets implicitly across sessions. There is no app-wide default for it either.

The user wants a unified, predictable behavior: when the user changes any of `viewMode`, `sortCriteria`, or `showHiddenFiles` for a folder, those choices are remembered for that folder and restored on next visit. If the user has not deviated, the folder follows the user's app-wide defaults.

## Goals

1. Persist `viewMode` per folder, alongside the existing two settings.
2. Add a user-configurable **default view mode** to General settings, mirroring the existing default-sort and default-hidden-files options.
3. Consolidate the three per-folder values into a single record per folder (`FolderViewSettings`) with a single `UserDefaults` key.
4. Migrate existing `folderSortOrders` and `folderShowHiddenFiles` data into the new shape on first launch, then delete the legacy keys.
5. Preserve the existing rule: a folder's settings are only stored when at least one field deviates from the app default. When all three return to the default, the folder's record is removed from the dict.

## Non-Goals

- No "Reset View Settings for This Folder" UI in this pass.
- No bookmark/inode-based folder identity. We continue to key by `url.path` string. If a folder is renamed or moved, its stored deviations are orphaned. This matches the current behavior and matches Finder's per-folder view memory characteristics in practice.
- No persistence of view settings for non-directory modes (`.tagQuery`, search results, network roots without a stable path). These continue to use the live in-memory values without being saved.
- No migration of view-mode state across panes. Each pane resolves its view mode on navigation from the store + default, just like sort/hidden today.

## Architecture

### New model: `FolderViewSettings`

New file: `BetterFinder/Models/FolderViewSettings.swift`

```swift
struct FolderViewSettings: Codable, Equatable {
    var viewMode: ViewMode?
    var sortCriteria: SortCriteria?
    var showHiddenFiles: Bool?

    var isEmpty: Bool {
        viewMode == nil && sortCriteria == nil && showHiddenFiles == nil
    }
}
```

Each field is optional. `nil` means "no deviation; inherit the app default at read time." The `isEmpty` helper drives removal of dead entries.

`ViewMode` is currently declared at the top of `FileListViewModel.swift` as a non-Codable enum. It is moved to `BetterFinder/Models/ViewMode.swift` and made `Codable`, `Equatable`, `Hashable`. Existing consumers (toolbar, file list views) keep working because the type name does not change.

### New service: `FolderViewSettingsStore`

New file: `BetterFinder/Services/FolderViewSettingsStore.swift`

Singleton (`shared`) that owns the path → settings dict and all `UserDefaults` I/O. Replaces the two static dicts and their save methods inside `FileListViewModel`.

API:

```swift
final class FolderViewSettingsStore {
    static let shared = FolderViewSettingsStore()

    func settings(for path: String) -> FolderViewSettings
    func update(for path: String, _ mutate: (inout FolderViewSettings) -> Void)
}
```

Behavior:

- `settings(for:)` returns the stored record or an all-nil `FolderViewSettings()` if none exists.
- `update(for:_:)` applies the mutation, then:
  - if `isEmpty`, removes the key from the dict;
  - otherwise stores the updated record;
  - persists the entire dict to `UserDefaults` under the key `folderViewSettings.v2`.
- All access is on the main actor (the store is only consumed from `FileListViewModel`, which is already main-actor-bound by way of being driven by SwiftUI views).

#### Migration

On first construction, the store checks for legacy data:

1. If a value exists at `UserDefaults` key `folderViewSettings.v2`, decode and use it. No migration needed.
2. Otherwise:
   - Read `folderSortOrders` (legacy `[String: SortCriteria]`).
   - Read `folderShowHiddenFiles` (legacy `[String]` of paths where hidden files were shown).
   - For every path in the union, build a `FolderViewSettings` with whichever fields apply.
   - Save under `folderViewSettings.v2`.
   - Remove both legacy keys.

Migration runs exactly once per install. If both legacy keys are absent, the store starts empty.

### `AppSettings` additions

In `BetterFinder/Models/AppSettings.swift`:

- Add `defaultViewMode: ViewMode` with `UserDefaults` key `settings.general.defaultViewMode`. Default value: `.list`.
- Persisted/loaded the same way as `defaultSortCriteria` (JSON-encoded since `ViewMode` is now `Codable`, or as raw string — implementer's choice; raw string is simpler).

### General settings UI

In whichever General settings view currently exposes "Default sort" and "Show hidden files by default" (under `BetterFinder/Views/Settings/`), add a **"Default view"** segmented control or picker bound to `AppSettings.shared.defaultViewMode` with two options: **List** and **Icons** (label matching what the toolbar uses for thumbnails view today).

## `FileListViewModel` Integration

### Reading settings (resolve)

A new private helper:

```swift
private func resolvedSettings(for path: String) -> (ViewMode, SortCriteria, Bool) {
    let stored = FolderViewSettingsStore.shared.settings(for: path)
    let defaults = AppSettings.shared
    return (
        stored.viewMode ?? defaults.defaultViewMode,
        stored.sortCriteria ?? defaults.defaultSortCriteria,
        stored.showHiddenFiles ?? defaults.showHiddenFilesByDefault
    )
}
```

Three places call this:

1. `init(startURL:)`
2. `navigate(to:)`
3. The two existing branches that re-resolve settings on history navigation (`goBack()` / `goForward()` regions around lines 392–405 of `FileListViewModel.swift`)

Each replaces the current pair of lookups (`folderSortOrders[...]`, `folderShowHiddenFiles.contains(...)`) and additionally sets `viewMode`.

### Writing settings (deviation tracking)

Three user actions trigger writes. Each compares against the current app default and either stores or clears the field. Writes only happen when `mode` is `.directory(_)`; in `.tagQuery` (and any future non-directory modes) toggles mutate the in-memory state but are not persisted, since there is no stable folder path to key on.

1. **`toggleHiddenFiles()`** (already exists):

   ```swift
   showHiddenFiles.toggle()
   FolderViewSettingsStore.shared.update(for: currentURL.path) { s in
       s.showHiddenFiles = (showHiddenFiles == AppSettings.shared.showHiddenFilesByDefault)
           ? nil
           : showHiddenFiles
   }
   ```

2. **`toggleSort(by:)`** (already exists):

   ```swift
   // existing logic to flip ascending or change field…
   FolderViewSettingsStore.shared.update(for: currentURL.path) { s in
       s.sortCriteria = (sortCriteria == AppSettings.shared.defaultSortCriteria)
           ? nil
           : sortCriteria
   }
   ```

   The current code special-cases `sortCriteria == .default` to remove the entry; this becomes "compare against `AppSettings.shared.defaultSortCriteria`" for consistency. (If `defaultSortCriteria` itself equals `.default`, the behavior matches today.)

3. **New: `setViewMode(_:)`**:

   ```swift
   func setViewMode(_ newMode: ViewMode) {
       viewMode = newMode
       FolderViewSettingsStore.shared.update(for: currentURL.path) { s in
           s.viewMode = (newMode == AppSettings.shared.defaultViewMode) ? nil : newMode
       }
   }
   ```

### View-mode wiring

Currently `MainContentView.swift` binds the toolbar's view-mode control directly to `$vm.viewMode` (raw `@Bindable` write). To route changes through `setViewMode(_:)` so deviation tracking can fire, the binding becomes a custom `Binding`:

```swift
viewMode: Binding(
    get: { viewModel.viewMode },
    set: { viewModel.setViewMode($0) }
)
```

The toolbar's `Binding<ViewMode>` parameter is unchanged.

### Cleanup of legacy state

Delete from `FileListViewModel`:

- `static let sortDefaultsKey`
- `static var folderSortOrders`
- `static func saveFolderSortOrders()`
- `static let hiddenFilesDefaultsKey`
- `static var folderShowHiddenFiles`
- `static func saveFolderShowHiddenFiles()`

All callers are replaced by `FolderViewSettingsStore.shared`.

## Data Flow Summary

```
                  AppSettings (defaults)
                          │
                          ▼
  navigate(to: url) ─► resolvedSettings(path) ─► viewModel.{viewMode, sortCriteria, showHiddenFiles}
                          ▲
                          │
            FolderViewSettingsStore (per-folder deviations)
                          ▲
                          │
  user toggles a setting ─┘  (write nil if matches default, else write value)
```

## Edge Cases

- **First-run with no defaults set.** App-wide defaults fall back to their built-in values (`.list`, `SortCriteria.default`, hidden-files-off). `FolderViewSettings` is empty; nothing is stored anywhere.
- **User changes the app-wide default after deviating per-folder.** A folder that previously matched the new default still has an explicit value stored — that's intentional; the user's per-folder choice was an explicit deviation at the time and we don't second-guess it. (This matches macOS Finder's behavior.)
- **User changes a setting back to the default.** The corresponding field is cleared (set to `nil`). If all three become `nil`, the folder's record is removed from the dict.
- **Tag-query / search modes.** `navigate(to:)` is not the entry point for these; the existing `mode = .tagQuery(...)` path bypasses settings resolution. View-mode toggles in those modes mutate `viewModel.viewMode` in memory only and are not persisted (because there's no path to key on). This is acceptable.
- **Corrupt or malformed legacy data.** If decoding `folderSortOrders` fails, that part of the migration is skipped (legacy code already tolerates this with a try-decoder fallback). The user keeps whatever can be migrated and loses what cannot.

## Testing

This codebase has no test suite (`CLAUDE.md`: "No test suite exists"). Verification is manual:

1. Build a fresh install, set defaults in General settings to e.g. List + name-ascending + hidden-off.
2. Navigate to folder A; toggle to thumbnails. Quit and relaunch. A opens in thumbnails. Other folders remain in list.
3. In folder A, toggle hidden files on, change sort to size-descending. Relaunch. All three deviations restored.
4. Toggle each setting back to the default in folder A. Inspect `defaults read com.example.BetterFinder folderViewSettings.v2`; folder A's record is gone.
5. Verify legacy migration: with a build of the old binary, deviate a couple of folders, then upgrade to the new binary; deviations carry over and `folderSortOrders` / `folderShowHiddenFiles` keys are deleted.
6. Visit a tag-query view; toggle view mode. Confirm no entry is written to the store.

## File Touch List

New:

- `BetterFinder/Models/FolderViewSettings.swift`
- `BetterFinder/Models/ViewMode.swift` (extracted from `FileListViewModel.swift`)
- `BetterFinder/Services/FolderViewSettingsStore.swift`

Modified:

- `BetterFinder/Models/AppSettings.swift` — add `defaultViewMode`.
- `BetterFinder/ViewModels/FileListViewModel.swift` — remove the two static dicts, add `setViewMode`, route reads/writes through the store, drop legacy `ViewMode` declaration.
- `BetterFinder/Views/MainContentView.swift` — change view-mode binding to call `setViewMode(_:)`.
- The General settings view (under `BetterFinder/Views/Settings/`) — add the default-view-mode picker.
