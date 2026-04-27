# App Settings Window — Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. This project has no test framework and no linter; verification is "build succeeds + manual check in the running app." Do not commit between tasks — the user will commit when they've tested.

**Goal:** Add an application Settings window (⌘, / `BetterFinder → Settings…`) with a Path Finder-style tab toolbar, scoped to a General tab containing three settings: show hidden files by default, default folder on launch, and default sort criteria.

**Architecture:** A single `@Observable` `AppSettings.shared` store persists to `UserDefaults`. SwiftUI's `Settings` scene holds a `SettingsView` shell that renders a custom tab bar and the active tab's content. `FileListViewModel.init` and `ContentView` consume `AppSettings` for initial state and for tracking the active pane's last location.

**Tech Stack:** SwiftUI, AppKit (for `NSOpenPanel`), `@Observable` macro, `UserDefaults`.

**Spec:** `docs/superpowers/specs/2026-04-26-app-settings-window-design.md`

---

## File Structure

**Create:**
- `BetterFinder/Models/AppSettings.swift` — observable settings store + UserDefaults persistence + `initialURL()` resolution
- `BetterFinder/Views/Settings/SettingsTab.swift` — enum of tabs with display label + SF Symbol
- `BetterFinder/Views/Settings/SettingsView.swift` — Settings window shell with custom tab bar
- `BetterFinder/Views/Settings/GeneralSettingsView.swift` — General tab Form contents

**Modify:**
- `BetterFinder/BetterFinderApp.swift` — add `Settings { SettingsView() }` scene
- `BetterFinder/ViewModels/FileListViewModel.swift` — `init` reads from `AppSettings`; per-folder fallback uses settings instead of hardcoded defaults
- `BetterFinder/ContentView.swift` — initial `sidebarSelection` mirrors initial URL; `onChange(of: activeVM.currentURL)` updates `lastLocationPath`

---

## Task 1: `AppSettings` model

**Files:**
- Create: `BetterFinder/Models/AppSettings.swift`

- [ ] **Step 1: Create the file with the full implementation**

```swift
import Foundation
import AppKit

enum DefaultLocation: String, Codable, CaseIterable, Identifiable {
    case home
    case lastLocation
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return "Home Folder"
        case .lastLocation: return "Last Location"
        case .custom: return "Custom…"
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - UserDefaults keys
    private enum Keys {
        static let showHiddenFilesByDefault = "settings.general.showHiddenFilesByDefault"
        static let defaultLocation = "settings.general.defaultLocation"
        static let customDefaultLocationPath = "settings.general.customDefaultLocationPath"
        static let lastLocationPath = "settings.general.lastLocationPath"
        static let defaultSortCriteria = "settings.general.defaultSortCriteria"
    }

    // MARK: - Stored settings
    var showHiddenFilesByDefault: Bool {
        didSet { UserDefaults.standard.set(showHiddenFilesByDefault, forKey: Keys.showHiddenFilesByDefault) }
    }

    var defaultLocation: DefaultLocation {
        didSet { UserDefaults.standard.set(defaultLocation.rawValue, forKey: Keys.defaultLocation) }
    }

    var customDefaultLocationPath: String {
        didSet { UserDefaults.standard.set(customDefaultLocationPath, forKey: Keys.customDefaultLocationPath) }
    }

    var lastLocationPath: String {
        didSet { UserDefaults.standard.set(lastLocationPath, forKey: Keys.lastLocationPath) }
    }

    var defaultSortCriteria: SortCriteria {
        didSet {
            if let data = try? JSONEncoder().encode(defaultSortCriteria) {
                UserDefaults.standard.set(data, forKey: Keys.defaultSortCriteria)
            }
        }
    }

    // MARK: - Init (loads from UserDefaults; falls back to defaults)
    private init() {
        let defaults = UserDefaults.standard

        self.showHiddenFilesByDefault = defaults.bool(forKey: Keys.showHiddenFilesByDefault)

        if let raw = defaults.string(forKey: Keys.defaultLocation),
           let loc = DefaultLocation(rawValue: raw) {
            self.defaultLocation = loc
        } else {
            self.defaultLocation = .home
        }

        self.customDefaultLocationPath = defaults.string(forKey: Keys.customDefaultLocationPath) ?? ""
        self.lastLocationPath = defaults.string(forKey: Keys.lastLocationPath) ?? ""

        if let data = defaults.data(forKey: Keys.defaultSortCriteria),
           let decoded = try? JSONDecoder().decode(SortCriteria.self, from: data) {
            self.defaultSortCriteria = decoded
        } else {
            self.defaultSortCriteria = .default
        }
    }

    // MARK: - Resolution helpers

    /// Returns the URL a fresh pane should open to, based on `defaultLocation`.
    /// Falls back to the home directory if the configured path is missing or unreadable.
    func initialURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch defaultLocation {
        case .home:
            return home
        case .lastLocation:
            return resolveDirectory(at: lastLocationPath) ?? home
        case .custom:
            return resolveDirectory(at: customDefaultLocationPath) ?? home
        }
    }

    private func resolveDirectory(at path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds with no errors.

---

## Task 2: `SettingsTab` enum

**Files:**
- Create: `BetterFinder/Views/Settings/SettingsTab.swift`

- [ ] **Step 1: Create the directory and file**

```swift
import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        }
    }

    /// SF Symbol name used in the settings tab bar.
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds.

---

## Task 3: `SettingsView` shell with custom tab bar

**Files:**
- Create: `BetterFinder/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 560, height: 520)
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: tab == selection,
                    action: { selection = tab }
                )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .frame(width: 36, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                Text(tab.label)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Note**

This will not build until `GeneralSettingsView` exists (Task 4). That's fine — verify after Task 4.

---

## Task 4: `GeneralSettingsView`

**Files:**
- Create: `BetterFinder/Views/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show hidden files by default", isOn: $settings.showHiddenFilesByDefault)
            } footer: {
                Text("New windows and panes will show files whose names start with a dot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Folder on Launch") {
                Picker("Open to:", selection: $settings.defaultLocation) {
                    ForEach(DefaultLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.menu)

                if settings.defaultLocation == .custom {
                    HStack {
                        Text("Folder:")
                        Text(displayPath(settings.customDefaultLocationPath))
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { chooseCustomFolder() }
                    }
                }
            }

            Section("Default Sort") {
                Picker("Sort by:", selection: $settings.defaultSortCriteria.field) {
                    Text("Name").tag(SortField.name)
                    Text("Date Modified").tag(SortField.dateModified)
                    Text("Size").tag(SortField.size)
                    Text("Kind").tag(SortField.kind)
                }
                .pickerStyle(.menu)

                Picker("Order:", selection: $settings.defaultSortCriteria.ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            } footer: {
                Text("Applies to folders that don't already have a remembered sort order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func displayPath(_ path: String) -> String {
        if path.isEmpty { return "(none selected)" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if !settings.customDefaultLocationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.customDefaultLocationPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.customDefaultLocationPath = url.path
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds (Tasks 3 + 4 together compile).

---

## Task 5: Add Settings scene to the app

**Files:**
- Modify: `BetterFinder/BetterFinderApp.swift`

- [ ] **Step 1: Add the `Settings` scene after the existing `WindowGroup`**

Current `body` (lines 8–39) ends with the closing `}` of `.commands { ... }` followed by `}` for `var body`. Insert a new `Settings { SettingsView() }` scene immediately after the closing `}` of the `WindowGroup`'s `.commands { }` modifier and before the closing `}` of `var body`.

The resulting `var body` should look like this (full replacement):

```swift
var body: some Scene {
    WindowGroup("") {
        ContentView()
    }
    .defaultSize(width: 1000, height: 650)
    .commands {
        CommandGroup(after: .newItem) {
            Button("Connect to Server...") {
                NotificationCenter.default.post(name: .connectToServer, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Button("Move to Trash") {
                guard let vm = activeVM, !vm.selectedItems.isEmpty else { return }
                vm.moveToTrash(vm.selectedItems)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   firstResponder is NSTextView {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                } else if let vm = activeVM {
                    vm.selectedItems = Set(vm.displayItems.map(\.id))
                }
            }
            .keyboardShortcut("a", modifiers: .command)
        }
    }

    Settings {
        SettingsView()
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds. The `BetterFinder → Settings…` menu item and ⌘, shortcut now exist.

- [ ] **Step 3: Manual smoke test (user)**

Launch the app, press ⌘,, confirm the Settings window opens with the General tab visible. Toggling controls should persist across relaunch.

---

## Task 6: Wire `FileListViewModel` to read defaults from `AppSettings`

**Files:**
- Modify: `BetterFinder/ViewModels/FileListViewModel.swift`

- [ ] **Step 1: Replace the `init` (currently lines 234–238)**

Replace the existing init:

```swift
init(startURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.navigationState = NavigationState(url: startURL)
    self.sortCriteria = Self.folderSortOrders[startURL.path] ?? .default
    self.showHiddenFiles = Self.folderShowHiddenFiles.contains(startURL.path)
}
```

with:

```swift
init(startURL: URL? = nil) {
    let resolvedStart = startURL ?? AppSettings.shared.initialURL()
    self.navigationState = NavigationState(url: resolvedStart)
    self.sortCriteria = Self.folderSortOrders[resolvedStart.path] ?? AppSettings.shared.defaultSortCriteria
    self.showHiddenFiles = Self.folderShowHiddenFiles.contains(resolvedStart.path)
        ? true
        : AppSettings.shared.showHiddenFilesByDefault
}
```

- [ ] **Step 2: Update `navigate(to:)` per-folder fallbacks (currently lines 246–256)**

Find the existing method:

```swift
func navigate(to url: URL) {
    expandedFolders.removeAll()
    childItems.removeAll()
    items = []
    isLoading = true
    rebuildDisplayItems()
    navigationState.navigate(to: url)
    sortCriteria = Self.folderSortOrders[url.path] ?? .default
    showHiddenFiles = Self.folderShowHiddenFiles.contains(url.path)
    Task { await reload() }
}
```

Change the two fallback lines so they consult `AppSettings`:

```swift
func navigate(to url: URL) {
    expandedFolders.removeAll()
    childItems.removeAll()
    items = []
    isLoading = true
    rebuildDisplayItems()
    navigationState.navigate(to: url)
    sortCriteria = Self.folderSortOrders[url.path] ?? AppSettings.shared.defaultSortCriteria
    showHiddenFiles = Self.folderShowHiddenFiles.contains(url.path)
        ? true
        : AppSettings.shared.showHiddenFilesByDefault
    Task { await reload() }
}
```

- [ ] **Step 3: Update the two other locations that read per-folder fallbacks (currently lines 325–326 and 333–334)**

These are inside back/forward navigation handlers. For both occurrences of the pattern:

```swift
sortCriteria = Self.folderSortOrders[currentURL.path] ?? .default
showHiddenFiles = Self.folderShowHiddenFiles.contains(currentURL.path)
```

replace with:

```swift
sortCriteria = Self.folderSortOrders[currentURL.path] ?? AppSettings.shared.defaultSortCriteria
showHiddenFiles = Self.folderShowHiddenFiles.contains(currentURL.path)
    ? true
    : AppSettings.shared.showHiddenFilesByDefault
```

Use `Edit` with sufficient surrounding context to disambiguate the two occurrences (or `replace_all` since both are identical).

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds.

---

## Task 7: Wire `ContentView` to use `AppSettings.initialURL()` and track last location

**Files:**
- Modify: `BetterFinder/ContentView.swift`

- [ ] **Step 1: Update initial `sidebarSelection` (currently line 88)**

Change:

```swift
@State private var sidebarSelection: URL? = FileManager.default.homeDirectoryForCurrentUser
```

to:

```swift
@State private var sidebarSelection: URL? = AppSettings.shared.initialURL()
```

This keeps the sidebar's highlighted item in sync with the pane that `FileListViewModel()`'s default init now opens.

- [ ] **Step 2: Add a `.onChange` observer that writes the active pane's current URL to `AppSettings.lastLocationPath`**

Find the existing `.onChange(of: fileListVM.currentURL) { _, _ in ... }` block (currently lines 282–287) and add a new sibling `.onChange` after it (and after the matching `secondFileListVM.currentURL` block at lines 288–293):

```swift
.onChange(of: activeVM.currentURL) { _, newURL in
    AppSettings.shared.lastLocationPath = newURL.path
}
```

Insert this new modifier between the existing `.onChange(of: secondFileListVM.currentURL) { ... }` block and `.onChange(of: showDualPane) { ... }`.

Note: `activeVM` is a computed property on `ContentView` that already returns the focused pane's view model based on `activePaneIsSecond`. Because `@Observable` tracks reads, this `onChange` fires whenever the active pane's URL changes — covering both panes correctly without duplicating the write.

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`
Expected: Build succeeds.

- [ ] **Step 4: Manual end-to-end test (user)**

1. Launch app → confirm it opens to Home.
2. Open Settings → set "Default Folder on Launch" = "Last Location".
3. Navigate to `~/Documents` in the active pane → quit → relaunch → confirm it opens to `~/Documents`.
4. Open Settings → set to "Custom…" and pick a folder → quit → relaunch → confirm it opens there.
5. Open Settings → toggle "Show hidden files by default" on → navigate to a fresh folder you've never visited → confirm hidden files appear.
6. Open Settings → set Default Sort = "Size, Descending" → navigate to a fresh folder → confirm new sort applied. Navigate to a folder with a remembered sort → confirm remembered sort still wins.

---

## Self-Review Notes (for the writer)

- All three settings from the spec are implemented (Tasks 1, 4, 6, 7).
- Active-pane-only last-location tracking is achieved via the `activeVM` computed property in `ContentView` — single onChange covers both panes, fires only for the focused one.
- No commits in steps; user commits after testing.
- No test framework, so verification = build + manual checklist.
- `SortField` is referenced in Task 4 — already exists in `Models/SortCriteria.swift`.
