# App Settings Window — Design

**Date:** 2026-04-26
**Status:** Approved (pending spec review)

## Goal

Introduce an application Settings window for BetterFinder, accessible via the standard `BetterFinder → Settings…` menu item (⌘,). Use a tab-toolbar layout (icon + label per tab) modeled after Path Finder's preferences window, scoped to a single **General** tab for v1. Establish the architecture so future tabs can be added by appending one enum case and one view file.

## Non-Goals (v1)

- Tabs other than General (Browser, Features, Appearance, Finder, etc.).
- "Reset Warnings" / "do not ask again" infrastructure.
- Confirmation toggle for moving items to Trash (Trash is reversible; permanent delete already has a confirmation).
- Restoring the last-opened settings tab between launches.
- Security-scoped bookmarks for the custom default-location folder (BetterFinder is non-sandboxed).

## Settings in the General Tab (v1)

1. **Show hidden files by default** — `Bool`, default `false`. Used as the initial value for new `FileListViewModel` instances when no per-folder override exists.
2. **Default folder on launch** — `enum DefaultLocation { home, lastLocation, custom }`, default `.home`.
   - `custom` is paired with a folder path chosen via `NSOpenPanel`.
   - `lastLocation` tracks the **active pane only** (not both panes).
3. **Default sort criteria** — `SortCriteria`, default `.default`. Applies only to *new* folders that have no remembered per-folder sort. Existing per-folder overrides are not affected.

## Architecture

### New files

- `Models/AppSettings.swift`
  - `enum DefaultLocation: String, Codable, CaseIterable { case home, lastLocation, custom }`
  - `@Observable final class AppSettings` with `static let shared`.
  - Properties: `showHiddenFilesByDefault`, `defaultLocation`, `customDefaultLocationPath`, `lastLocationPath`, `defaultSortCriteria`.
  - Each property has a `didSet` that persists to `UserDefaults` (Codable types serialized to JSON `Data`).
  - `func initialURL() -> URL` resolves the launch folder per `defaultLocation`, falling back to home if the resolved path is missing/inaccessible.

- `Views/Settings/SettingsTab.swift`
  - `enum SettingsTab: String, CaseIterable, Identifiable { case general }`
  - Provides `label: String` and `systemImage: String` so the tab bar renders consistently.

- `Views/Settings/SettingsView.swift`
  - Top-level container. Holds selected-tab state and renders a custom toolbar-style tab bar above the active tab's content. Width matched to the screenshot proportions; height grows with content.
  - The tab bar is a simple `HStack` of buttons with selected-state styling (accent-tinted icon + label) so it visually matches Path Finder's screenshot rather than the default macOS `TabView` chrome.

- `Views/Settings/GeneralSettingsView.swift`
  - SwiftUI `Form` bound to `AppSettings.shared`.
  - Sections separated by dividers (matching the screenshot's grouping).
  - Custom-folder picker uses `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`).

### Modifications

- `BetterFinderApp.swift`
  - Add `Settings { SettingsView() }` scene. macOS auto-creates the `BetterFinder → Settings…` menu item with ⌘, — no manual `CommandGroup` needed.

- `ViewModels/FileListViewModel.swift`
  - `init(startURL: URL = AppSettings.shared.initialURL())` — replaces the current `homeDirectoryForCurrentUser` default.
  - Initial `showHiddenFiles` and `sortCriteria` use the per-folder override if present, otherwise fall back to the corresponding `AppSettings` value (instead of the hardcoded defaults).
  - `navigate(to:)` (and any other path that updates `currentURL`) writes `AppSettings.shared.lastLocationPath` *only when this VM is the active pane*. Active-pane awareness is derived from the existing `@FocusedValue(\.activeFileListVM)` mechanism — the VM does not need to know directly; instead, `ContentView` (which already tracks focus) updates `lastLocationPath` when the active pane's `currentURL` changes.

## Data Flow

```
User edits General tab
    └── AppSettings.shared.<property> = newValue
            └── didSet → UserDefaults.standard.set(...)

App launches
    └── ContentView creates FileListViewModel()
            └── init reads AppSettings.shared.initialURL() and defaults

Active pane navigates
    └── ContentView observes activeFileListVM.currentURL
            └── writes AppSettings.shared.lastLocationPath
```

## Persistence

- Keys are namespaced under `"settings.general."` (e.g. `settings.general.showHiddenFilesByDefault`).
- `Bool` and `String` use the native UserDefaults setters.
- `DefaultLocation` is stored as its `rawValue` string.
- `SortCriteria` (already `Codable`) is JSON-encoded to `Data`.
- Reads happen once during `AppSettings.init`; thereafter the in-memory `@Observable` properties are the source of truth.

## Error Handling

- Missing/invalid persisted values fall back to their compile-time defaults silently.
- `initialURL()` validates path existence with `FileManager.fileExists(atPath:isDirectory:)`; on failure returns `homeDirectoryForCurrentUser`.
- `NSOpenPanel` cancellation leaves the previous custom path unchanged.

## Testing

No automated test suite exists in the project. Manual verification:
- Open Settings via menu and ⌘,. Confirm tab bar renders.
- Toggle "Show hidden files by default" → relaunch → new pane respects it.
- Switch default location across Home / Last location / Custom; relaunch and verify each.
- Change default sort; navigate to a fresh folder with no remembered sort; verify the new sort is used. Verify a folder with an existing per-folder sort is unaffected.
- Verify `BetterFinder → Settings…` menu item appears and the keyboard shortcut works.
