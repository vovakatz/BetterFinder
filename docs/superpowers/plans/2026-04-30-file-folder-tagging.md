# File & Folder Tagging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This project has no test framework and no linter; verification is "build succeeds + manual check in the running app." Do not commit between tasks — the user will commit when they've tested.

**Goal:** Add Finder-compatible file/folder tagging to BetterFinder, surfaced as colored dots in the file list, a right-click tag picker, an Info widget editor, and sidebar virtual folders backed by Spotlight.

**Architecture:** Tags are stored using the macOS system mechanism (`URLResourceKey.tagNamesKey`). A new `TagService` reads/writes per-file tags and reads the tag catalog (name/color/favorites) from `com.apple.finder` defaults. A new `TagQueryService` wraps `NSMetadataQuery` for sidebar virtual folders. `FileListViewModel` gains a `Mode` enum so the same view can render either a directory or a flat tag-results virtual folder.

**Tech Stack:** Swift 5.9+, SwiftUI (`@Observable`), AppKit (`NSTokenField`, `NSMetadataQuery`, FSEvents), `URLResourceKey.tagNamesKey`, `com.apple.finder` defaults read via `UserDefaults(suiteName:)`.

**Spec:** `docs/superpowers/specs/2026-04-30-file-folder-tagging-design.md`

**Build command:** `xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet`

**Run for manual verification:** `./build_and_install.sh && open /Applications/BetterFinder.app`

---

## Design deviation noted up front

The spec proposed a horizontal row of colored dots at the top of the right-click context menu, matching Finder's UX exactly. SwiftUI's `.contextMenu` does not support a horizontal row of independent clickable buttons within a menu item. Replicating Finder's exact layout would require dropping to AppKit `NSMenu` for the entire per-item context menu, which is significantly larger than the scope of this feature.

This plan delivers the same **functional capability** via a SwiftUI-native vertical submenu: `Tags ▸` opens a submenu with one item per favorite tag (colored dot icon + name + checkmark when applied). One click toggles. The "Tags…" item is added below the submenu and opens the token-field popover.

A true horizontal dot row remains possible as a polish follow-up by introducing a small AppKit-hosted context menu helper. It is **not** included in this plan.

---

## File Structure

**Create:**

- `BetterFinder/Models/FileTag.swift` — `FileTag` value type, `TagColor` enum, color → SwiftUI `Color` mapping.
- `BetterFinder/Services/TagService.swift` — `@Observable` service: tag catalog (loaded from `com.apple.finder` defaults), per-URL read/write, toggle helper, catalog refresh on app activation.
- `BetterFinder/Services/TagQueryService.swift` — `NSMetadataQuery` wrapper for "all files with tag X". One instance per active tag-results view.
- `BetterFinder/Services/TagFSEventsObserver.swift` — FSEvents stream for the visible directory; reports xattr modifications so tag changes from Finder are picked up live.
- `BetterFinder/Views/FileList/TagDotsView.swift` — small SwiftUI view rendering up to 3 trailing colored circles.
- `BetterFinder/Views/Tags/TagPickerTokenField.swift` — `NSViewRepresentable` wrapper around `NSTokenField` with autocomplete and color rendering. Reusable.
- `BetterFinder/Views/Tags/TagPickerPopover.swift` — popover wrapper around `TagPickerTokenField`, used by the "Tags…" menu item.

**Modify:**

- `BetterFinder/Models/FileItem.swift` — add `tags: [FileTag]`; update `==`.
- `BetterFinder/Services/FileSystemService.swift` — request `.tagNamesKey`, populate `FileItem.tags` via `TagService`.
- `BetterFinder/ViewModels/FileListViewModel.swift` — add `Mode` enum (`.directory(URL)` / `.tagQuery(FileTag)`), `openTagQuery(_:)`, gate directory monitor on `.directory`, route population from `TagQueryService` in `.tagQuery` mode.
- `BetterFinder/Views/FileList/FileRowView.swift` — append `TagDotsView` to the Name column.
- `BetterFinder/Views/FileList/FileListView.swift` — add `Tags ▸` submenu and `Tags…` item to the per-item context menu; show empty/loading state for tag-query mode.
- `BetterFinder/Views/Widgets/InfoWidgetView.swift` — add a "Tags" row using `TagPickerTokenField` inline.
- `BetterFinder/Views/Sidebar/SidebarView.swift` — add `Tags` section with rows per favorite tag, virtual `tag:///<name>` URLs.
- `BetterFinder/Views/PathBar/PathBarView.swift` — render a non-navigable tag segment (colored dot + "Tag: <name>") when in tag-query mode.
- `BetterFinder/ContentView.swift` — when `sidebarSelection` has scheme `tag`, decode the tag and call `activeVM.openTagQuery(tag)` instead of `navigate(to:)`.

---

## Task 1: `FileTag` model + `TagColor` enum

**Files:**
- Create: `BetterFinder/Models/FileTag.swift`

- [ ] **Step 1: Create the file with the full implementation**

```swift
import SwiftUI

/// macOS tag color index. Mirrors the values stored under the `l` key in
/// the `Tags` array in `com.apple.finder` defaults, and the index Finder
/// shows in its tag editor.
enum TagColor: Int, CaseIterable, Hashable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    /// SwiftUI rendering color tuned to match Finder's actual hues.
    var swiftUIColor: Color {
        switch self {
        case .none:   return Color(white: 0.75)
        case .gray:   return Color(red: 0.66, green: 0.66, blue: 0.69)
        case .green:  return Color(red: 0.46, green: 0.79, blue: 0.36)
        case .purple: return Color(red: 0.74, green: 0.45, blue: 0.83)
        case .blue:   return Color(red: 0.27, green: 0.55, blue: 0.95)
        case .yellow: return Color(red: 0.97, green: 0.82, blue: 0.30)
        case .red:    return Color(red: 0.94, green: 0.34, blue: 0.34)
        case .orange: return Color(red: 0.95, green: 0.59, blue: 0.27)
        }
    }

    /// `true` when this color renders as a hollow ring rather than a filled disk.
    var rendersAsRing: Bool { self == .none }
}

struct FileTag: Hashable, Identifiable {
    let name: String
    let color: TagColor

    var id: String { name }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Run:

```bash
ls /Users/vladimirkatz/Dev/BetterFinder/BetterFinder/Models/FileTag.swift
```

Expected: file path printed.

Open `BetterFinder.xcodeproj` in Xcode and drag `Models/FileTag.swift` into the BetterFinder target's `Models` group, OR rely on the project's `*.swift` file globbing if configured. (Existing project does NOT use globbing; the file must be added to the target. Confirm by inspecting `BetterFinder.xcodeproj/project.pbxproj` for an existing model entry like `FileItem.swift` and adding a parallel entry for `FileTag.swift`.)

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`. If "Cannot find type 'FileTag' in scope" appears in any later task, the file was not added to the target — return to Step 2.

---

## Task 2: `TagService` — catalog (read Finder prefs)

**Files:**
- Create: `BetterFinder/Services/TagService.swift`

- [ ] **Step 1: Create the file with the catalog-only implementation**

```swift
import Foundation
import AppKit

/// Source of truth for the tag catalog and per-file tag I/O.
///
/// The catalog (available tags, their colors, and the sidebar favorites
/// list) is read from Finder's preferences (`com.apple.finder` defaults).
/// BetterFinder is a read-only consumer of that catalog — users continue
/// to manage tags in Finder Settings → Tags.
@Observable
final class TagService {
    static let shared = TagService()

    /// Full catalog: every tag name → its color.
    private(set) var catalog: [String: TagColor] = [:]

    /// All known tags sorted by name. Used by the picker for autocomplete.
    private(set) var availableTags: [FileTag] = []

    /// Sidebar favorites in order. `nil` entries represent separators
    /// (Finder stores empty strings as separators in `FavoriteTagNames`).
    private(set) var favoriteTags: [FileTag?] = []

    private init() {
        loadCatalog()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        loadCatalog()
    }

    /// Resolves a list of raw tag names into `FileTag` values using the catalog.
    /// Names not in the catalog are returned with color `.none`.
    func resolve(names: [String]) -> [FileTag] {
        names.map { FileTag(name: $0, color: catalog[$0] ?? .none) }
    }

    private func loadCatalog() {
        let defaults = UserDefaults(suiteName: "com.apple.finder")

        // Tags: array of dicts with at least keys "n" (name, String) and
        // "l" (color index, Int 0–7). Other keys (e.g. "p" for some
        // metadata) are ignored.
        var newCatalog: [String: TagColor] = [:]
        if let rawTags = defaults?.array(forKey: "Tags") as? [[String: Any]] {
            for entry in rawTags {
                guard let name = entry["n"] as? String, !name.isEmpty else { continue }
                let colorIndex = (entry["l"] as? Int) ?? 0
                let color = TagColor(rawValue: colorIndex) ?? .none
                newCatalog[name] = color
            }
        }

        // Fall back to the seven Finder default tags if the catalog is empty
        // (parse failure or fresh user with no customization).
        if newCatalog.isEmpty {
            newCatalog = Self.defaultCatalog
        }

        // FavoriteTagNames: ordered array of strings. Empty strings act as
        // separators in Finder's sidebar; we treat them the same.
        var newFavorites: [FileTag?] = []
        if let rawFavorites = defaults?.array(forKey: "FavoriteTagNames") as? [String] {
            for name in rawFavorites {
                if name.isEmpty {
                    newFavorites.append(nil)
                } else {
                    let color = newCatalog[name] ?? .none
                    newFavorites.append(FileTag(name: name, color: color))
                }
            }
        }

        // If no favorites configured, default to all named catalog tags.
        if newFavorites.isEmpty {
            newFavorites = Self.defaultCatalog.keys.sorted().map { name in
                FileTag(name: name, color: Self.defaultCatalog[name] ?? .none)
            }
        }

        let newAvailable = newCatalog
            .map { FileTag(name: $0.key, color: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        catalog = newCatalog
        availableTags = newAvailable
        favoriteTags = newFavorites
    }

    /// Hardcoded fallback matching Finder's seven default color tags.
    private static let defaultCatalog: [String: TagColor] = [
        "Red":    .red,
        "Orange": .orange,
        "Yellow": .yellow,
        "Green":  .green,
        "Blue":   .blue,
        "Purple": .purple,
        "Gray":   .gray,
    ]
}
```

- [ ] **Step 2: Add the file to the Xcode project (same as Task 1 Step 2)**

- [ ] **Step 3: Add a temporary launch-time log to verify catalog parsing**

In `BetterFinder/BetterFinderApp.swift`, find the app's `body` or `init` and add a one-time print after app launch. The simplest way is at the top of `ContentView`'s `.task { ... }` block, add:

```swift
print("TagService catalog:", TagService.shared.catalog)
print("TagService favorites:", TagService.shared.favoriteTags.map { $0?.name ?? "<separator>" })
```

(Find this `.task` in `ContentView.swift` around line 312 — `.task { fileListVM.clipboardService = ... }`.)

- [ ] **Step 4: Build, run, and verify the log**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && ./build_and_install.sh
open /Applications/BetterFinder.app
```

Open Console.app, filter on "BetterFinder", or run from terminal:

```bash
/Applications/BetterFinder.app/Contents/MacOS/BetterFinder 2>&1 | grep TagService
```

Expected: prints a non-empty catalog. If you have customized tags in Finder (Finder → Settings → Tags), they should appear. If the user has not customized, the seven default Finder tags should appear (Red, Orange, Yellow, Green, Blue, Purple, Gray).

If the catalog is empty: `UserDefaults(suiteName: "com.apple.finder")` returned nothing. This can happen if the binary lacks read access to other apps' preferences. Workaround for non-sandboxed builds: read directly from `~/Library/SyncedPreferences/com.apple.finder.plist` or call `CFPreferencesCopyAppValue("FavoriteTagNames" as CFString, "com.apple.finder" as CFString)`. Pause and report — do not paper over with the default fallback if the user expects their custom tags.

- [ ] **Step 5: Remove the temporary print statements**

---

## Task 3: `TagService` — read/write tag I/O

**Files:**
- Modify: `BetterFinder/Services/TagService.swift`

- [ ] **Step 1: Add the I/O methods to `TagService`**

Append the following methods inside the `TagService` class (before the final closing brace, after `loadCatalog()`):

```swift
    // MARK: - Per-URL tag I/O

    /// Reads tags for a single URL. Returns `[]` for non-local volumes,
    /// missing files, or any error (callers cannot meaningfully recover
    /// from a per-URL read failure).
    func tags(for url: URL) -> [FileTag] {
        guard url.isFileURL else { return [] }
        let values = try? url.resourceValues(forKeys: [.tagNamesKey])
        let names = values?.tagNames ?? []
        return resolve(names: names)
    }

    /// Writes a tag set to a list of URLs.
    ///
    /// Each URL is attempted independently. On any failure, throws
    /// `TagWriteError` containing the per-URL outcomes so callers can
    /// update in-memory state for the URLs that did succeed.
    func setTags(_ tags: [FileTag], on urls: [URL]) throws {
        var failures: [(URL, Error)] = []
        var successes: [URL] = []

        let names = tags.map(\.name)

        for url in urls {
            // Non-local volumes silently fail to write tags. Detect and
            // surface as a recognizable error.
            let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? false
            guard url.isFileURL && isLocal else {
                failures.append((url, TagIOError.unsupportedVolume))
                continue
            }

            do {
                var mutableURL = url
                var resourceValues = URLResourceValues()
                resourceValues.tagNames = names
                try mutableURL.setResourceValues(resourceValues)
                successes.append(mutableURL)

                // If the user introduced a tag name that wasn't in the
                // catalog yet, add it with color .none so the picker and
                // dot view can render it immediately.
                for tag in tags where catalog[tag.name] == nil {
                    catalog[tag.name] = tag.color
                }
                if !tags.isEmpty {
                    availableTags = catalog
                        .map { FileTag(name: $0.key, color: $0.value) }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            } catch {
                failures.append((url, error))
            }
        }

        if !failures.isEmpty {
            throw TagWriteError(successes: successes, failures: failures)
        }
    }

    /// Toggle behaviour: if every URL has the tag, removes it from all;
    /// otherwise adds it to every URL that doesn't have it.
    func toggle(_ tag: FileTag, on urls: [URL]) throws {
        let allHave = urls.allSatisfy { tags(for: $0).contains(tag) }
        for url in urls {
            var current = tags(for: url)
            if allHave {
                current.removeAll { $0 == tag }
            } else if !current.contains(tag) {
                current.append(tag)
            }
            try setTags(current, on: [url])
        }
    }
}

enum TagIOError: Error {
    case unsupportedVolume
}

struct TagWriteError: Error {
    let successes: [URL]
    let failures: [(URL, Error)]

    var localizedDescription: String {
        if failures.contains(where: {
            if case TagIOError.unsupportedVolume = $0.1 { return true }
            return false
        }) {
            return "Tags can't be applied to files on this volume."
        }
        return "Couldn't apply tags to \(failures.count) item\(failures.count == 1 ? "" : "s")."
    }
}
```

(Note: the closing brace `}` at the top of the appended snippet closes the `TagService` class. The `loadCatalog` method ends with `}`; you are placing the new methods between `loadCatalog`'s closing brace and the existing class closing brace, then keeping the type definitions for `TagIOError` and `TagWriteError` after the class.)

- [ ] **Step 2: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

Verification beyond build is deferred to Task 4, where this is wired into `FileSystemService`.

---

## Task 4: `FileItem.tags` + `FileSystemService` integration

**Files:**
- Modify: `BetterFinder/Models/FileItem.swift`
- Modify: `BetterFinder/Services/FileSystemService.swift`

- [ ] **Step 1: Add `tags` to `FileItem`**

In `BetterFinder/Models/FileItem.swift`, add `let tags: [FileTag]` to the stored properties (after `fileSizeDisplay`). Update the initializer to accept it with a default of `[]`. Update the `Equatable` conformance to include tags.

Replace the current struct body (lines 4-58) with:

```swift
struct FileItem: Identifiable {
    let id: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let fileSize: Int64
    let dateModified: Date?
    let kind: String
    let icon: NSImage
    let deferredIconURL: URL?
    let dateModifiedDisplay: String
    let fileSizeDisplay: String
    let tags: [FileTag]

    var url: URL { id }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(
        id: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool,
        isHidden: Bool,
        fileSize: Int64,
        dateModified: Date?,
        kind: String,
        icon: NSImage,
        deferredIconURL: URL? = nil,
        dateModifiedDisplay: String? = nil,
        fileSizeDisplay: String? = nil,
        tags: [FileTag] = []
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.fileSize = fileSize
        self.dateModified = dateModified
        self.kind = kind
        self.icon = icon
        self.deferredIconURL = deferredIconURL
        self.dateModifiedDisplay = dateModifiedDisplay ?? {
            guard let dateModified else { return "--" }
            return Self.dateFormatter.string(from: dateModified)
        }()
        self.fileSizeDisplay = fileSizeDisplay ?? (isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        self.tags = tags
    }
}
```

Replace the `Equatable` extension (lines 60-66 of the original) with:

```swift
extension FileItem: Equatable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
            && lhs.fileSize == rhs.fileSize
            && lhs.dateModified == rhs.dateModified
            && lhs.tags == rhs.tags
    }
}
```

- [ ] **Step 2: Update `FileSystemService` to read and populate tags**

In `BetterFinder/Services/FileSystemService.swift`:

Replace the `resourceKeys` set (lines 5-13) with:

```swift
    nonisolated static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
        .tagNamesKey,
    ]
```

Replace the `LoadedFileMetadata` struct (lines 15-24) with:

```swift
    private struct LoadedFileMetadata: Sendable {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isPackage: Bool
        let isHidden: Bool
        let fileSize: Int64
        let dateModified: Date?
        let kind: String
        let tagNames: [String]
    }
```

In `loadMetadata(of:showHiddenFiles:sortedBy:)`, replace the `LoadedFileMetadata(...)` construction inside the `compactMap` (lines 79-88) with:

```swift
            return LoadedFileMetadata(
                url: url,
                name: values.name ?? url.lastPathComponent,
                isDirectory: isDir && !isPackage,
                isPackage: isPackage,
                isHidden: values.isHidden ?? false,
                fileSize: Int64(values.fileSize ?? 0),
                dateModified: values.contentModificationDate,
                kind: values.localizedTypeDescription ?? "Unknown",
                tagNames: values.tagNames ?? []
            )
```

In `loadContents(of:showHiddenFiles:sortedBy:)`, replace the `metadata.map { item in ... }` block (lines 45-58) with:

```swift
        return metadata.map { item in
            FileItem(
                id: item.url,
                name: item.name,
                isDirectory: item.isDirectory,
                isPackage: item.isPackage,
                isHidden: item.isHidden,
                fileSize: item.fileSize,
                dateModified: item.dateModified,
                kind: item.kind,
                icon: FileIconProvider.shared.placeholderIcon(isDirectory: item.isDirectory),
                deferredIconURL: item.url,
                tags: TagService.shared.resolve(names: item.tagNames)
            )
        }
```

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

Verification: tags on items are now read but not displayed. Visual verification comes in Task 6.

---

## Task 5: `TagDotsView` component

**Files:**
- Create: `BetterFinder/Views/FileList/TagDotsView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// Trailing colored circles next to a filename, one per tag.
/// Hidden entirely when `tags` is empty (no layout space reserved).
struct TagDotsView: View {
    let tags: [FileTag]

    private static let dotDiameter: CGFloat = 8
    private static let dotOverlap: CGFloat = 1
    private static let maxDots: Int = 3

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            let visible = Array(tags.prefix(Self.maxDots))
            HStack(spacing: -Self.dotOverlap) {
                ForEach(Array(visible.enumerated()), id: \.element.name) { _, tag in
                    dot(for: tag)
                }
            }
            .help(tags.map(\.name).joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func dot(for tag: FileTag) -> some View {
        if tag.color.rendersAsRing {
            Circle()
                .strokeBorder(Color.gray.opacity(0.6), lineWidth: 1)
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
        } else {
            Circle()
                .fill(tag.color.swiftUIColor)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 6: Wire `TagDotsView` into `FileRowView`

**Files:**
- Modify: `BetterFinder/Views/FileList/FileRowView.swift`

- [ ] **Step 1: Insert `TagDotsView` after the filename `Text`**

In `FileRowView.body`, locate the `else` branch of the rename conditional that renders the filename `Text` (lines 48-57 of `FileRowView.swift`). Replace that single `Text(...)` block with the `Text` followed by `TagDotsView`:

```swift
                if isRenaming {
                    RenameTextField(
                        text: $renameText,
                        onCommit: onCommitRename,
                        onCancel: onCancelRename,
                        fontSize: 12
                    )
                    .frame(height: 18)
                } else {
                    HStack(spacing: 4) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .fontWeight(item.isDirectory ? .bold : .regular)
                            .foregroundStyle(item.isHidden ? .gray : .primary)
                            .layoutPriority(1)
                            .contentShape(Rectangle())
                            .onHover { onNameHover?($0) }
                        TagDotsView(tags: item.tags)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
```

- [ ] **Step 2: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification — visible tag dots**

Set up: in **Finder**, tag a few files in `~/Documents` or another local folder with one or more colors (right-click → choose a color). If you have no tagged files, do this now before running BetterFinder.

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && ./build_and_install.sh
open /Applications/BetterFinder.app
```

Navigate to the folder where you tagged files. Verify:

- Files with one tag show a single colored circle to the right of the filename.
- Files with multiple tags show up to 3 overlapping circles.
- Files with no tags show no circle (no extra spacing).
- Hovering over the dots shows a tooltip listing the tag names.
- Colors approximately match Finder's rendering of the same tags.

If the dots don't appear: check that `tags` was wired through `FileSystemService` in Task 4 by adding a temporary `print(item.tags)` in `FileRowView.body` and re-running.

---

## Task 7: `TagPickerTokenField` (`NSTokenField` wrapper)

**Files:**
- Create: `BetterFinder/Views/Tags/TagPickerTokenField.swift`

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p /Users/vladimirkatz/Dev/BetterFinder/BetterFinder/Views/Tags
```

Then create `BetterFinder/Views/Tags/TagPickerTokenField.swift`:

```swift
import SwiftUI
import AppKit

/// SwiftUI wrapper around `NSTokenField` that displays each token as a
/// colored dot + name, with autocomplete sourced from the current tag
/// catalog. Editing commits the new tag list via the `onCommit` closure.
struct TagPickerTokenField: NSViewRepresentable {
    /// The current tag list. Bound so external changes (selection
    /// replaced, etc.) reset the field.
    @Binding var tags: [FileTag]

    /// Available tags for autocomplete.
    let availableTags: [FileTag]

    /// Called when the user commits a change (Return, blur, or token
    /// add/remove). Receives the new tag list.
    var onCommit: ([FileTag]) -> Void = { _ in }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.tokenStyle = .rounded
        field.delegate = context.coordinator
        field.completionDelay = 0.1
        field.font = .systemFont(ofSize: 11)
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        field.objectValue = tags.map(\.name)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        let currentNames = (field.objectValue as? [String]) ?? []
        let desiredNames = tags.map(\.name)
        if currentNames != desiredNames {
            field.objectValue = desiredNames
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: TagPickerTokenField

        init(parent: TagPickerTokenField) {
            self.parent = parent
        }

        // Autocomplete from the catalog.
        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            let matches = parent.availableTags
                .map(\.name)
                .filter { $0.localizedCaseInsensitiveContains(substring) }
            return matches
        }

        // Commit on every change (token added or removed).
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTokenField else { return }
            commit(field)
        }

        // Commit on blur and Return.
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTokenField else { return }
            commit(field)
        }

        private func commit(_ field: NSTokenField) {
            let names = (field.objectValue as? [String]) ?? []
            let resolved = names.map { name -> FileTag in
                if let known = parent.availableTags.first(where: { $0.name == name }) {
                    return known
                }
                return FileTag(name: name, color: .none)
            }
            parent.onCommit(resolved)
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

Verification deferred to Task 9 (popover) and Task 10 (Info widget integration), where this is first visible.

---

## Task 8: Right-click context menu — `Tags ▸` submenu

**Files:**
- Modify: `BetterFinder/Views/FileList/FileListView.swift`

This task adds a `Tags ▸` submenu to the per-item context menu. Each row in the submenu shows a colored dot + tag name + checkmark when the tag is applied to all selected items. Clicking toggles the tag on the selection.

- [ ] **Step 1: Add a helper for collecting tags applied to a selection**

Inside `FileListView`'s body section (after `private var isNetworkContext` near line 385, before `contextMenuContent`), add:

```swift
    private func tagsApplied(toAll urls: Set<URL>) -> Set<FileTag> {
        guard !urls.isEmpty else { return [] }
        let perFile = urls.map { Set(TagService.shared.tags(for: $0)) }
        guard let first = perFile.first else { return [] }
        return perFile.dropFirst().reduce(first) { $0.intersection($1) }
    }

    private func toggleTag(_ tag: FileTag, on urls: Set<URL>) {
        do {
            try TagService.shared.toggle(tag, on: Array(urls))
            Task { await viewModel.refreshTags(for: urls) }
        } catch let error as TagWriteError {
            viewModel.errorMessage = error.localizedDescription
            Task { await viewModel.refreshTags(for: Set(error.successes)) }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
```

(`viewModel.refreshTags(for:)` is added in Step 3.)

- [ ] **Step 2: Insert the `Tags ▸` submenu and `Tags…` item into the context menu**

In `contextMenuContent(forSelection:)` (line 391), find where the existing per-item items are added (around the `if scheme != "network"` block). Inside that block, after the existing `Button("Show in Finder") { ... }` action and before the `if isSingle, let item = primaryItem` block, insert:

```swift
            Divider()

            let appliedToAll = tagsApplied(toAll: targetURLs)
            Menu("Tags") {
                ForEach(TagService.shared.favoriteTags.compactMap { $0 }) { tag in
                    Button {
                        toggleTag(tag, on: targetURLs)
                    } label: {
                        Label {
                            HStack {
                                Text(tag.name)
                                if appliedToAll.contains(tag) {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        } icon: {
                            Circle()
                                .fill(tag.color.swiftUIColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                Divider()
                Button("Tags…") {
                    tagPickerAnchor = targetURLs
                    showTagPicker = true
                }
            }
```

- [ ] **Step 3: Add `refreshTags(for:)` to `FileListViewModel` and the picker state**

In `BetterFinder/ViewModels/FileListViewModel.swift`, add the method (place near other refresh methods; if uncertain, place at the end of the class before the final closing brace):

```swift
    /// Re-reads tag values for a subset of URLs and updates `items` in
    /// place. Used after a local tag write to avoid a full directory
    /// reload.
    @MainActor
    func refreshTags(for urls: Set<URL>) async {
        for url in urls {
            guard let index = items.firstIndex(where: { $0.id == url }) else { continue }
            let existing = items[index]
            let newTags = TagService.shared.tags(for: url)
            guard newTags != existing.tags else { continue }
            items[index] = FileItem(
                id: existing.id,
                name: existing.name,
                isDirectory: existing.isDirectory,
                isPackage: existing.isPackage,
                isHidden: existing.isHidden,
                fileSize: existing.fileSize,
                dateModified: existing.dateModified,
                kind: existing.kind,
                icon: existing.icon,
                deferredIconURL: existing.deferredIconURL,
                dateModifiedDisplay: existing.dateModifiedDisplay,
                fileSizeDisplay: existing.fileSizeDisplay,
                tags: newTags
            )
        }
    }
```

- [ ] **Step 4: Add picker presentation state to `FileListView`**

At the top of `FileListView`'s `@State` declarations, add:

```swift
    @State private var showTagPicker: Bool = false
    @State private var tagPickerAnchor: Set<URL> = []
```

(The popover content view is added in Task 9.)

- [ ] **Step 5: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`. The "Tags…" button does nothing yet — the popover comes in Task 9.

- [ ] **Step 6: Manual verification — toggleable tag submenu**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && ./build_and_install.sh
open /Applications/BetterFinder.app
```

In a folder with files:

- Right-click a file. Verify a `Tags` submenu appears below "Show in Finder".
- Hover the submenu. Verify it lists each favorite tag with a colored dot icon and the tag name.
- Click a tag. Verify the menu dismisses and the file's dot indicator updates immediately.
- Right-click the same file again. Verify the toggled tag now has a checkmark.
- Click it again to remove. Verify the dot disappears.
- Select multiple files (some with the tag, some without). Right-click → Tags → click that tag. Verify the tag is added to all (since not all had it). Right-click again → it now shows checkmark. Click → removed from all.
- Open Finder and navigate to the same folder. Verify the tag changes are reflected there.

---

## Task 9: `TagPickerPopover` and the "Tags…" item

**Files:**
- Create: `BetterFinder/Views/Tags/TagPickerPopover.swift`
- Modify: `BetterFinder/Views/FileList/FileListView.swift`

- [ ] **Step 1: Create the popover view**

```swift
import SwiftUI

/// Popover that hosts a tag picker for one or more selected files.
/// Computes the union (and per-file intersection) of tags across the
/// selection, lets the user edit, and writes the diff back via `TagService`.
struct TagPickerPopover: View {
    let urls: Set<URL>
    var onClose: () -> Void = {}

    @State private var workingTags: [FileTag] = []
    @State private var initialTagsByURL: [URL: Set<FileTag>] = [:]
    @State private var didLoad: Bool = false

    private let tagService = TagService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TagPickerTokenField(
                tags: $workingTags,
                availableTags: tagService.availableTags,
                onCommit: { newTags in
                    workingTags = newTags
                    applyDiff(newTags: newTags)
                }
            )
            .frame(minWidth: 220, minHeight: 28)

            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
        .onAppear { loadInitial() }
    }

    private func loadInitial() {
        guard !didLoad else { return }
        didLoad = true
        var byURL: [URL: Set<FileTag>] = [:]
        for url in urls {
            byURL[url] = Set(tagService.tags(for: url))
        }
        initialTagsByURL = byURL

        // For multi-selection, present the union; tokens applied to all
        // files render solid (token field has no per-token styling here,
        // so the user sees the union and edits affect the diff).
        let union = byURL.values.reduce(into: Set<FileTag>()) { $0.formUnion($1) }
        workingTags = union.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func applyDiff(newTags: [FileTag]) {
        let newSet = Set(newTags)
        for (url, prior) in initialTagsByURL {
            let added = newSet.subtracting(prior)
            let removed = prior.subtracting(newSet)
            if added.isEmpty && removed.isEmpty { continue }

            var current = tagService.tags(for: url)
            for tag in removed {
                current.removeAll { $0 == tag }
            }
            for tag in added {
                if !current.contains(tag) { current.append(tag) }
            }
            do {
                try tagService.setTags(current, on: [url])
            } catch {
                // Best-effort; surface elsewhere is the caller's job.
            }
        }
        // Refresh the snapshot so subsequent edits apply against the new state.
        var byURL: [URL: Set<FileTag>] = [:]
        for url in urls {
            byURL[url] = Set(tagService.tags(for: url))
        }
        initialTagsByURL = byURL
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

- [ ] **Step 3: Attach the popover to the file list**

In `BetterFinder/Views/FileList/FileListView.swift`, find the outer `body` view (the table or list that has the `.contextMenu` modifier around line 283). Add a `.popover` modifier to the same view (sibling to `.contextMenu`):

```swift
        .popover(isPresented: $showTagPicker, arrowEdge: .trailing) {
            TagPickerPopover(urls: tagPickerAnchor, onClose: {
                showTagPicker = false
                Task { await viewModel.refreshTags(for: tagPickerAnchor) }
            })
        }
```

(Place this near other view modifiers — `.contextMenu`, `.onChange`, etc. — at the end of the modifier chain on the table/list view.)

- [ ] **Step 4: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification — tag picker popover**

Run the app. Right-click a file → Tags → Tags…. Verify:

- A popover appears with a token field labeled "Tags".
- Existing tags appear as tokens.
- Type "Foo" + Return → "Foo" appears as a new token; the file in the list gains a new dot (color `.none`, hollow ring) immediately or after Done.
- Backspace removes the trailing token; the corresponding tag disappears from the file.
- Close the popover (Done or Escape). Tag changes persist.
- Open Finder and verify the same file shows the same tag set.
- Right-click multiple files → Tags…. Verify the popover shows the **union** of tags across the selection. Editing applies the diff (additions go to all selected files; removals only affect files that had the tag).

Note: the multi-selection "dimmed token for partial application" UX from the spec is not implemented in this pass — the token field simply shows the union and applies a diff. This is a known simplification; revisit if it confuses users.

---

## Task 10: Info widget — Tags row

**Files:**
- Modify: `BetterFinder/Views/Widgets/InfoWidgetView.swift`

- [ ] **Step 1: Add a `tagsRow` helper to `InfoWidgetView`**

Add a method on `InfoWidgetView` (place near other `private func ... -> some View` helpers, e.g. after `infoRow(_:_:)` near line 665):

```swift
    @ViewBuilder
    private func tagsRow(for urls: [URL]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("Tags")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(.secondary)
            TagsField(urls: urls)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
    }
```

Add a small wrapper `TagsField` view at file scope (above `InfoWidgetView` or below, but inside the same file):

```swift
private struct TagsField: View {
    let urls: [URL]
    @State private var workingTags: [FileTag] = []
    @State private var loaded: Bool = false

    private let tagService = TagService.shared

    var body: some View {
        TagPickerTokenField(
            tags: $workingTags,
            availableTags: tagService.availableTags,
            onCommit: { newTags in
                workingTags = newTags
                applyToAll(newTags)
            }
        )
        .frame(minHeight: 24)
        .onAppear(perform: load)
        .onChange(of: urls) { _, _ in load() }
    }

    private func load() {
        let union = urls.reduce(into: Set<FileTag>()) { acc, url in
            acc.formUnion(tagService.tags(for: url))
        }
        workingTags = union.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        loaded = true
    }

    private func applyToAll(_ newTags: [FileTag]) {
        let newSet = Set(newTags)
        for url in urls {
            let prior = Set(tagService.tags(for: url))
            let added = newSet.subtracting(prior)
            let removed = prior.subtracting(newSet)
            if added.isEmpty && removed.isEmpty { continue }
            var current = tagService.tags(for: url)
            for tag in removed { current.removeAll { $0 == tag } }
            for tag in added where !current.contains(tag) { current.append(tag) }
            try? tagService.setTags(current, on: [url])
        }
    }
}
```

- [ ] **Step 2: Render the Tags row in single and multi-select detail views**

In `metadataDetailView(url:meta:imageMeta:)` (line 413), at the very top of the `VStack`, before `infoRow("Name", meta.name)`, insert:

```swift
            tagsRow(for: [url])
            Divider().padding(.vertical, 4)
```

(Renders the tag row first so it's prominent.)

In `multiSelectView` (line 338), the existing implementation iterates per-selected-URL. We add a single shared Tags row at the top of the scroll view, applying to the full selection. Modify `multiSelectView`:

```swift
    private var multiSelectView: some View {
        let sorted = selectedURLs.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tagsRow(for: Array(selectedURLs))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                ForEach(sorted, id: \.self) { url in
                    multiSelectItemRow(url)
                }
            }
            .padding(.vertical, 4)
        }
    }
```

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification — Info widget tag editor**

Run the app. Make sure the Info widget is visible (it's the default top widget in the right panel). Click a tagged file in the list. Verify:

- The Info widget shows a "Tags" row near the top with current tags as tokens.
- Typing a new tag name + Return adds it; the dot indicator in the file list updates.
- Removing a token via backspace removes the tag.
- Selecting multiple files shows the union of their tags. Editing applies the diff.
- Tags persist (visible in Finder).

---

## Task 11: `TagQueryService` (NSMetadataQuery wrapper)

**Files:**
- Create: `BetterFinder/Services/TagQueryService.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import AppKit
import UniformTypeIdentifiers

/// Wraps `NSMetadataQuery` to enumerate all files tagged with a given
/// `FileTag` across the local computer + user home scope. One instance
/// per active tag-results view; deliver results via `onUpdate`.
final class TagQueryService {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning: Bool = false

    var onUpdate: (([FileItem]) -> Void)?
    var onGatheringFinished: (() -> Void)?

    func start(for tag: FileTag) {
        stop()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemUserTags == %@", tag.name)
        query.searchScopes = [
            NSMetadataQueryLocalComputerScope,
            NSMetadataQueryUserHomeScope,
        ]
        query.notificationBatchingInterval = 0.5

        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.publishResults(from: query)
            self?.onGatheringFinished?()
        })

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.publishResults(from: query)
        })

        self.query = query
        isRunning = true
        query.start()
    }

    func stop() {
        if let query = query {
            query.stop()
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
        }
        query = nil
        isRunning = false
    }

    private func publishResults(from query: NSMetadataQuery) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var items: [FileItem] = []
        items.reserveCapacity(query.resultCount)
        for i in 0..<query.resultCount {
            guard let result = query.result(at: i) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            if let item = Self.makeFileItem(from: url) {
                items.append(item)
            }
        }
        onUpdate?(items)
    }

    /// Synchronous lightweight `FileItem` from a URL. Resource keys
    /// requested are the same as `FileSystemService.resourceKeys`.
    private static func makeFileItem(from url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: FileSystemService.resourceKeys) else {
            return nil
        }
        let isDir = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        return FileItem(
            id: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: isDir && !isPackage,
            isPackage: isPackage,
            isHidden: values.isHidden ?? false,
            fileSize: Int64(values.fileSize ?? 0),
            dateModified: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? "Unknown",
            icon: FileIconProvider.shared.placeholderIcon(isDirectory: isDir),
            deferredIconURL: url,
            tags: TagService.shared.resolve(names: values.tagNames ?? [])
        )
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

- [ ] **Step 3: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

Verification deferred to Task 13 where the service is wired into the UI.

---

## Task 12: `FileListViewModel.Mode` + `openTagQuery`

**Files:**
- Modify: `BetterFinder/ViewModels/FileListViewModel.swift`

- [ ] **Step 1: Add `Mode` enum and storage**

At the top of `FileListViewModel` (after the existing `enum ViewMode`), add:

```swift
enum FileListMode: Equatable {
    case directory(URL)
    case tagQuery(FileTag)
}
```

Inside the class (with other stored properties, near `var navigationState: NavigationState`), add:

```swift
    var mode: FileListMode = .directory(URL(fileURLWithPath: NSHomeDirectory()))
    private let tagQueryService = TagQueryService()
```

(The default `directory(home)` is replaced as soon as `init` or `navigate(to:)` runs; this is just a non-optional placeholder.)

- [ ] **Step 2: Add `openTagQuery(_:)` and the close path**

Add a method on `FileListViewModel`:

```swift
    @MainActor
    func openTagQuery(_ tag: FileTag) {
        // Stop any prior query.
        tagQueryService.stop()

        mode = .tagQuery(tag)
        items = []
        isLoading = true
        errorMessage = nil
        selectedItems = []

        tagQueryService.onUpdate = { [weak self] newItems in
            guard let self else { return }
            self.items = newItems
            // Apply existing sort/filter pipeline. If your project has a
            // sortAndFilter helper, call it here. Otherwise, items render
            // in NSMetadataQuery order, which is fine for first pass.
            self.isLoading = false
        }
        tagQueryService.onGatheringFinished = { [weak self] in
            self?.isLoading = false
        }

        tagQueryService.start(for: tag)
    }
```

- [ ] **Step 3: Switch `mode` to `.directory` on regular navigation**

Find the existing `navigate(to:)` method in `FileListViewModel` (search for `func navigate`). At the top of its body, add:

```swift
        tagQueryService.stop()
        mode = .directory(url)
```

(If `navigate(to:)` is `async`, ensure these run on the main actor.)

Find the directory-monitor start/stop calls in `FileListViewModel`. Gate them on `if case .directory = mode` so they don't start a watch on a non-directory tag-query "location."

- [ ] **Step 4: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`. If "Property 'currentURL' has no setter" or similar shows up, you may need to adapt `currentURL` (used elsewhere) to derive from `mode`. In that case, change `var currentURL: URL` to a computed property:

```swift
    var currentURL: URL {
        switch mode {
        case .directory(let url): return url
        case .tagQuery(let tag): return URL(string: "tag:///\(tag.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag.name)") ?? URL(fileURLWithPath: "/")
        }
    }
```

Verification deferred to Task 13.

---

## Task 13: Sidebar Tags section + ContentView routing + path bar

**Files:**
- Modify: `BetterFinder/Views/Sidebar/SidebarView.swift`
- Modify: `BetterFinder/ContentView.swift`
- Modify: `BetterFinder/Views/PathBar/PathBarView.swift`
- Modify: `BetterFinder/Views/FileList/FileListView.swift` (empty/loading state)

- [ ] **Step 1: Add Tags section to the sidebar**

In `BetterFinder/Views/Sidebar/SidebarView.swift`, locate the `List` body (around line 32). After the "Locations" section closes (around line 71) but before the closing brace of `List`, add:

```swift
            Section(header: Text("Tags").fontWeight(.bold)) {
                ForEach(Array(TagService.shared.favoriteTags.enumerated()), id: \.offset) { offset, tagOpt in
                    if let tag = tagOpt {
                        let url = TagSidebarURL.make(name: tag.name)
                        Label {
                            Text(tag.name)
                        } icon: {
                            Circle()
                                .fill(tag.color.swiftUIColor)
                                .frame(width: 10, height: 10)
                        }
                        .tag(url)
                    } else {
                        Divider()
                    }
                }
            }
```

At the top of the file (after `import SwiftUI`), add the URL helper:

```swift
enum TagSidebarURL {
    static let scheme = "tag"

    static func make(name: String) -> URL {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "\(scheme):///\(encoded)")!
    }

    /// Returns the decoded tag name if this URL represents a sidebar tag entry.
    static func tagName(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let path = url.path
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.removingPercentEncoding ?? trimmed
    }
}
```

- [ ] **Step 2: Route tag URLs in `ContentView`**

In `BetterFinder/ContentView.swift`, find the `.onChange(of: sidebarSelection)` block (line 305). Replace it with:

```swift
        .onChange(of: sidebarSelection) { _, newURL in
            guard let url = newURL else { return }
            if let tagName = TagSidebarURL.tagName(from: url) {
                let known = TagService.shared.availableTags.first { $0.name == tagName }
                let tag = known ?? FileTag(name: tagName, color: .none)
                Task { @MainActor in activeVM.openTagQuery(tag) }
            } else {
                activeVM.navigate(to: url)
            }
        }
```

- [ ] **Step 3: Render tag-mode segment in the path bar**

In `BetterFinder/Views/PathBar/PathBarView.swift`, replace the entire file with:

```swift
import SwiftUI

struct PathBarView: View {
    enum Content {
        case path(components: [(name: String, url: URL)])
        case tag(name: String, color: Color)
    }

    let content: Content
    let onNavigate: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            switch content {
            case .path(let components):
                HStack(spacing: 2) {
                    ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button { onNavigate(component.url) } label: {
                            Text(component.name)
                                .font(.system(size: 11))
                                .foregroundStyle(index == components.count - 1 ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            case .tag(let name, let color):
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text("Tag: \(name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .frame(height: 20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

Find every call site of `PathBarView(components:onNavigate:)` (likely in `MainContentView.swift` or similar; grep for `PathBarView(`). Update each call site to use the new `content:` parameter:

For directory mode:

```swift
PathBarView(
    content: .path(components: viewModel.pathComponents),
    onNavigate: { viewModel.navigate(to: $0) }
)
```

For tag-query mode (sibling branch using `viewModel.mode`):

```swift
switch viewModel.mode {
case .directory:
    PathBarView(
        content: .path(components: viewModel.pathComponents),
        onNavigate: { viewModel.navigate(to: $0) }
    )
case .tagQuery(let tag):
    PathBarView(
        content: .tag(name: tag.name, color: tag.color.swiftUIColor),
        onNavigate: { _ in }
    )
}
```

- [ ] **Step 4: Add empty/loading state for tag-query mode**

In `BetterFinder/Views/FileList/FileListView.swift`, near the top of the table/list body, wrap with conditional empty state. Find where the file list table is rendered. Add an overlay or conditional:

```swift
        .overlay {
            if case .tagQuery(let tag) = viewModel.mode {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.items.isEmpty {
                    Text("No files tagged \(tag.name).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
```

- [ ] **Step 5: Handle double-click on a folder in tag mode**

In `FileListView`, find the existing double-click / open handler. Where it currently calls `viewModel.navigate(to: item.url)` for folders, no change is needed — `navigate` already resets `mode` to `.directory` per Task 12 Step 3.

- [ ] **Step 6: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual verification — sidebar tag virtual folder**

Run the app:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && ./build_and_install.sh
open /Applications/BetterFinder.app
```

Verify:

- The sidebar has a "Tags" section after Locations, listing each favorite tag (per Finder Settings → Tags) with a colored circle.
- Clicking a tag entry switches the file list to a flat view of all files with that tag, drawn from the user home + local computer scope. Initial result may take 1-3 seconds; "Searching…" appears briefly.
- The path bar shows "● Tag: Red" (or whatever) instead of a folder breadcrumb.
- Tag a new file in Finder. Within ~2 seconds, the new file appears in the BetterFinder tag-results list (live update).
- Untag a file in Finder. Within ~2 seconds, the file disappears from the list.
- Double-clicking a folder in tag results navigates into that folder (path bar reverts to a normal breadcrumb).
- Selecting a sidebar tag with no matching files shows "No files tagged X."
- Right-clicking a file in tag-results shows the context menu including the Tags submenu, and tag operations work.

---

## Task 14: FSEvents xattr listener for live tag updates in current folder

**Files:**
- Create: `BetterFinder/Services/TagFSEventsObserver.swift`
- Modify: `BetterFinder/ViewModels/FileListViewModel.swift`

This task picks up tag changes made externally (e.g., in Finder) for files in the directory the user is currently viewing in BetterFinder. Without this, the user must navigate away and back to see tag changes from other apps.

- [ ] **Step 1: Create the observer**

```swift
import Foundation
import CoreServices

/// Watches a single directory for extended-attribute modifications and
/// reports per-file changes. Used to pick up tag changes made by Finder
/// or other apps while BetterFinder is showing the same folder.
final class TagFSEventsObserver {
    private var stream: FSEventStreamRef?
    var onXattrChange: ((URL) -> Void)?

    func start(watching directory: URL) {
        stop()

        let pathsToWatch = [directory.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, contextInfo, numEvents, eventPaths, eventFlags, _ in
            guard let contextInfo else { return }
            let observer = Unmanaged<TagFSEventsObserver>.fromOpaque(contextInfo).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            for i in 0..<numEvents {
                let flags = eventFlags[i]
                if flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
                    let path = paths[i]
                    let url = URL(fileURLWithPath: path)
                    DispatchQueue.main.async {
                        observer.onXattrChange?(url)
                    }
                }
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

- [ ] **Step 3: Wire into `FileListViewModel`**

In `BetterFinder/ViewModels/FileListViewModel.swift`, add a stored property near the `tagQueryService` declaration:

```swift
    private let xattrObserver = TagFSEventsObserver()
```

In `init` (or wherever the directory monitor is set up), after `init` runs the first navigation, configure the observer:

```swift
    private func setupXattrObserver() {
        xattrObserver.onXattrChange = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshTags(for: [url])
            }
        }
    }
```

Call `setupXattrObserver()` from `init`.

In `navigate(to:)` (or wherever `mode` switches to `.directory`), after the navigation completes successfully, add:

```swift
        if case .directory(let url) = mode {
            xattrObserver.start(watching: url)
        } else {
            xattrObserver.stop()
        }
```

In `openTagQuery(_:)`, also call `xattrObserver.stop()`.

- [ ] **Step 4: Build**

Run:

```bash
cd /Users/vladimirkatz/Dev/BetterFinder && xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification — live xattr updates**

Run the app and navigate to a folder with tagged files. Open Finder side-by-side at the same folder. In Finder, change a file's tags. Verify:

- Within ~1 second, the BetterFinder file row's dot indicator updates to match.
- Adding a tag to an untagged file shows new dots without refreshing the folder.
- Removing all tags from a file removes its dots.

If updates don't appear: confirm BetterFinder is not sandboxed (FSEvents requires an entitlement under sandbox). Check Console.app for any FSEvents error. Add a temporary `print("xattr change:", url)` inside the callback closure to verify events fire.

---

## Final manual verification

After all tasks are complete and verified independently, run through this end-to-end checklist with the app installed and running:

- [ ] Launch BetterFinder. Tags catalog matches Finder Settings → Tags (favorites in same order, same colors).
- [ ] Navigate to a folder. Files with tags show colored dots; files without tags show no dot indicator.
- [ ] Right-click a file → Tags ▸ → click a tag. Dot updates immediately. Verify in Finder.
- [ ] Right-click again → tag has a checkmark.
- [ ] Right-click a file → Tags ▸ → Tags…. Type a brand-new tag name + Return. Token appears, hollow ring dot appears. Verify in Finder.
- [ ] Multi-select files, right-click → Tags ▸ → click a tag. Toggles based on whether all had it.
- [ ] Info widget Tags row works for single and multi selection.
- [ ] Sidebar Tags section shows favorites. Click one — flat virtual folder appears with "Tag: X" path bar.
- [ ] Empty tag virtual folder shows "No files tagged X."
- [ ] Tag a file in Finder while viewing the same folder in BetterFinder — dots update within ~1 sec.
- [ ] Tag a file in Finder while viewing the same tag's virtual folder in BetterFinder — file appears within ~2 sec.
- [ ] Try to tag a file on a network share (if available) — error message surfaces; no crash.
- [ ] Tag with special characters: open Finder Settings → Tags, create "Q&A!" — verify it round-trips through the BetterFinder sidebar.
- [ ] Quit and relaunch — tag catalog and dots persist (stored on the files themselves, so they should).

---

## Self-Review

**Spec coverage:**

| Spec section | Plan task |
|---|---|
| Goal — Finder-compatible tag storage | Tasks 3, 4 (URLResourceKey.tagNamesKey) |
| Scope A — color dots in list | Tasks 5, 6 |
| Scope C — context menu picker | Tasks 8, 9 |
| Scope D — Info widget editor | Task 10 |
| Scope E — sidebar virtual folders | Tasks 11, 12, 13 |
| Tag catalog from Finder prefs | Task 2 |
| FileTag / TagColor model | Task 1 |
| TagService read/write API | Task 3 |
| TagQueryService | Task 11 |
| FileListViewModel.Mode | Task 12 |
| Sidebar virtual `tag://` URLs | Task 13 |
| Path bar tag-mode segment | Task 13 |
| Live updates via FSEvents xattr | Task 14 |
| Edge: non-local volume | Task 3 (TagIOError.unsupportedVolume) |
| Edge: catalog parse failure fallback | Task 2 |
| Edge: empty tag-query result | Task 13 |
| Edge: special chars in tag name | Task 13 (`TagSidebarURL`) |

**Deviations from spec, called out:**

- Context menu uses `Tags ▸` vertical submenu instead of horizontal dot row. Documented at top of plan.
- Multi-selection token field shows union and applies diff, rather than the spec's "dimmed token for partial application" UX. Documented in Task 9.
- Tag deleted-in-Finder while shown in BetterFinder sidebar: the plan doesn't add an explicit "Tag no longer exists" empty state for an active tag-query view whose tag was deleted; the catalog refresh removes the sidebar row, but the active query persists with stale tag name. Acceptable for first pass; if the user revisits via Back/Forward, NSMetadataQuery still returns whatever files have that tag name.

**Type/name consistency check:**

- `FileTag`, `TagColor`, `TagService.shared`, `TagQueryService`, `TagPickerTokenField`, `TagPickerPopover`, `TagDotsView`, `TagFSEventsObserver`, `FileListMode`, `TagSidebarURL` — all referenced consistently across tasks.
- `TagService.toggle(_:on:)` is `throws`; callers in Task 8 catch `TagWriteError`. Consistent.
- `FileListViewModel.refreshTags(for:)` is `@MainActor async`; all callers `await` it inside `Task { ... }`. Consistent.
- `URLResourceValues.tagNames` — public Swift API, returns `[String]?`. Used consistently.

**Placeholder scan:** No TODO / TBD / "implement later" / "similar to Task N". All code blocks are concrete. Verification commands are exact. ✓
