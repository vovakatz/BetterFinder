# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build release and install to /Applications
./build_and_install.sh

# Build only (debug)
xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet

# Build release only
xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Release -quiet
```

No test suite exists. No linter is configured.

## Architecture

BetterFinder is a macOS file manager built with SwiftUI, following MVVM. All source lives in `BetterFinder/`.

**Layout hierarchy** (`ContentView.swift`):
```
HSplitView
├── SidebarView (favorites, volumes, network)
├── Center area
│   ├── Dual-pane FileListView (toggleable)
│   ├── BottomPanelView (resizable, optional)
│   └── StatusBarView
└── RightPanelView (VSplitView with 2 widget slots)
```

**Key layers:**

- **Models/** — Data types: `FileItem`, `NavigationState`, `SidebarItem`, `WidgetType`, `SortCriteria`, `NetworkItem`, `TerminalTheme`
- **ViewModels/** — `FileListViewModel` (core: file browsing, selection, file ops, directory monitoring, search) and `SidebarViewModel` (favorites, volumes)
- **Services/** — System integrations: `FileSystemService`, `NetworkService` (Bonjour/SMB), `GitService`, `SystemMonitorService`, `ClipboardService`, `TerminalSession`, `VolumeService`
- **Views/** — SwiftUI views organized by feature (file list, sidebar, toolbar, widgets, network sheets)
- **Extensions/** — Helpers on `URL`, `Date`, `Int64`

**Widgets** are swappable panels (defined by `WidgetType` enum): Terminal, Preview (QuickLook), Info, Git, Images, Clipboard, System Monitor. Each rendered via `WidgetSlotView`.

**Data flow:** `ContentView` owns layout state. Each pane gets its own `FileListViewModel`. `ClipboardService` is injected via SwiftUI environment. Active pane tracked via `FocusedValue`. Directory changes are monitored in real-time using `DispatchSourceFileSystemObject`.

## Dependencies

Single external dependency: **SwiftTerm** (terminal emulation), managed via Swift Package Manager.

## Patterns & Conventions

- Uses `@Observable` macro (not `ObservableObject`) for reactive state
- Keyboard shortcuts defined in `BetterFinderApp.swift` via `.commands { }` and `.onKeyPress` in views
- Search uses glob pattern matching (converted to regex), not substring search
- Network browsing uses `NWBrowser` for Bonjour discovery and `smbutil` CLI for share enumeration
- File operations go through `FileListViewModel` which coordinates with `ClipboardService`
- Drag-and-drop uses custom `DropDelegate` implementations
