# BetterFinder

A powerful, feature-rich macOS file manager built with SwiftUI. BetterFinder brings dual-pane browsing, integrated widgets, network browsing, and a modern interface to macOS file management.

![macOS](https://img.shields.io/badge/platform-macOS-blue)
![Swift](https://img.shields.io/badge/language-Swift-orange)
![SwiftUI](https://img.shields.io/badge/framework-SwiftUI-green)

---

## Features

### Multi-Pane Layout

- **Three-panel design** — left sidebar, center file area, and right widget panel
- **Dual-pane mode** — side-by-side independent file browsers with adjustable split
- **Bottom panel** — optional resizable panel below the file area for an additional widget
- **Fully resizable** — all panels and splits have drag handles with persisted sizing
- **Active pane indicator** — accent-colored bar highlights which pane has focus

### File Browsing

- **List view** — traditional column-based file list with Name, Date Modified, Size, and Kind
- **Thumbnail/Grid view** — adaptive grid with QuickLook-generated thumbnails
- **Inline folder expansion** — tree-style disclosure triangles to expand folders without navigating away
- **Hidden files toggle** — show or hide hidden files per-pane
- **Sortable columns** — click column headers to sort by Name, Date, Size, or Kind (ascending/descending)
- **Resizable columns** — drag column header dividers to adjust widths
- **Real-time directory monitoring** — file list updates automatically when files change on disk
- **Empty/error state handling** — clear messages for empty folders, permission errors, and Full Disk Access prompts

### Navigation

- **Back/Forward history** — full navigation history with back and forward buttons
- **Parent directory** — navigate up one level
- **Breadcrumb path bar** — clickable, scrollable path components from volume root to current directory. Click the current directory or empty area to edit the path directly
- **Network-aware breadcrumbs** — displays Network > Host > Share > path when inside mounted network shares
- **Sidebar navigation** — click any sidebar item to navigate instantly

### File Operations

- **Create** — new files and new folders via toolbar buttons, context menu, or keyboard shortcuts
- **Rename** — click-pause-click inline rename with automatic filename stem selection (extension preserved)
- **Copy / Cut / Paste** — full clipboard operations with conflict detection and overwrite confirmation
- **Move to Trash** — reversible deletion via system Trash
- **Permanent Delete** — irreversible deletion with confirmation dialog
- **Compress** — create ZIP archives from selected files/folders with resource fork preservation
- **Select All** — select all displayed items
- **Open With** — submenu listing all compatible applications, currently running apps, and a file picker for custom app selection

### Drag and Drop

- **Drag files** — drag from file list with custom preview showing icon and filename
- **Drop onto pane** — drop files into the current directory with move/copy confirmation
- **Drop onto folders** — drop directly onto folder rows with visual highlight feedback
- **Modifier key support** — hold Cmd while dropping to copy instead of move

### Search

- **Glob pattern matching** — supports `*` and `?` wildcards for powerful file filtering
- **Substring matching** — plain text searches match anywhere in filenames (case-insensitive)
- **Debounced input** — 250ms delay prevents excessive filtering during typing
- **Auto-clear on navigation** — search resets when changing directories
- **Per-pane search** — applies to the currently active pane only

### Sidebar

- **Favorites** — Home, Desktop, Documents, Downloads, Applications, and Trash
- **Custom favorites** — drag folders from the file list onto the sidebar to add them
- **Drag to reorder** — rearrange favorites by dragging
- **Remove favorites** — right-click to remove custom entries
- **Persistent favorites** — sidebar favorites are saved across app restarts
- **Volumes** — automatically lists all mounted local and external drives
- **Network volumes** — shows mounted remote volumes with one-click eject button
- **Auto-refresh** — volume list updates when drives are mounted or unmounted

### Network Browsing

- **Bonjour discovery** — automatically discovers SMB and AFP network hosts on the local network
- **SMB share enumeration** — browse available shares on discovered hosts
- **Mount network shares** — mount SMB/AFP shares directly from the file browser
- **Connect to Server** — manually connect via `smb://` or `afp://` URL
- **Authentication** — username/password dialog with guest access option
- **Keychain integration** — optionally save and auto-fill network credentials from the macOS Keychain
- **Recent servers** — quick reconnect to previously used server addresses

### Widgets

BetterFinder includes seven swappable widget panels that can be placed in the right panel (two slots) or the bottom panel. Widget selections are persisted across sessions.

#### Info Widget
- Comprehensive file metadata: name, kind, UTI, size (logical and physical), dates (created, modified, last opened)
- File attributes: hidden, readable, writable, executable
- Ownership and permissions in rwx and octal notation
- Volume info: name, capacity, free space, filesystem format, mount point
- **Image metadata**: pixel dimensions, color model/profile, bit depth, DPI
- **EXIF data**: camera make/model, lens, exposure, aperture, ISO, focal length, flash, white balance, metering mode
- **GPS coordinates**: latitude, longitude, altitude
- **Directory size calculation**: on-demand recursive size computation

#### Preview Widget
- **Text files** — editable with monospaced font and save button
- **Images** — inline display with aspect ratio preservation
- **PDFs** — rendered via PDFKit in continuous single-page mode
- **Fallback** — attempts UTF-8 text rendering for unknown file types

#### Terminal Widget
- **Full terminal emulator** — powered by SwiftTerm, running zsh as a login shell
- **Auto-sync** — terminal automatically `cd`s to match the file browser's current directory
- **9 built-in themes** — Default, 12-bit Rainbow, Aardvark Blue, Adventure, Adventure Time, Belafonte Night, Chester, Cutie Pro, Flat
- **Theme persistence** — selected theme saved across sessions
- **Clear button** — quick terminal clear

#### Git Widget
- **Repository detection** — automatically identifies git repositories
- **Branch info** — current branch name with ahead/behind remote indicators
- **File status** — color-coded list of all staged, unstaged, and untracked changes (Modified, Added, Deleted, Renamed, Untracked, Conflicted)
- **Stage/Unstage** — per-file or bulk stage/unstage operations
- **Commit** — compose and create commits directly from the widget
- **Push** — push to remote with progress indicator and pending commit count
- **Recent commits** — last 20 commits with hash, message, author, and relative date

#### Images Gallery Widget
- **Image grid** — displays all images in the current directory in an adaptive grid
- **QuickLook thumbnails** — high-quality thumbnail generation
- **Click to select** — single click selects the image in the file browser
- **Double-click to open** — opens with the default image viewer

#### Clipboard Manager Widget
- **Operation history** — tracks up to 50 copy/cut operations per session
- **Visual badges** — CUT (orange) and COPY (blue) labels on each entry
- **File preview** — shows first 3 filenames per entry with item count
- **Restore** — restore any previous clipboard entry as the active clipboard
- **Remove** — delete individual entries from history
- **Clear all** — wipe entire clipboard history
- **System clipboard sync** — all operations sync with the macOS system pasteboard

#### System Monitor Widget
- **CPU** — usage bar, total/user/system percentages, process count, load averages (1/5/15 min)
- **Memory** — usage bar, used/free/total/wired/compressed/swap breakdown
- **GPU** — usage percentage (when available via IOKit)
- **Battery** — charge level, charging status, time remaining, cycle count
- **Disk I/O** — read/write rates and total bytes transferred
- **Network** — download/upload rates and total traffic across all interfaces
- **System** — uptime and load averages
- **Configurable refresh** — 0.5s, 1s, 2s, or 5s update intervals

### Context Menus

- **File context menu** — Open, Open With, Show in Finder, Copy Path/Reference (name, absolute path, or home-relative path), Rename, Cut, Copy, Paste, Move to Trash, Delete, Compress
- **Background context menu** — New Folder, New File, Paste
- **Sidebar context menu** — Remove custom favorites

### Keyboard Shortcuts

- **Cmd+C** — Copy
- **Cmd+X** — Cut
- **Cmd+V** — Paste
- **Cmd+A** — Select All
- **Cmd+Delete** — Move to Trash
- **Cmd+K** — Connect to Server
- **Return** — Open selected item
- **Escape** — Cancel rename

### Persistence

All layout preferences, widget selections, sidebar favorites, terminal theme, and recent server addresses are automatically saved and restored across app sessions.

---

## Build & Install

### Requirements

- macOS (built with SwiftUI)
- Xcode
- Swift Package Manager (for SwiftTerm dependency)

### Quick Start

```bash
# Build release and install to /Applications
./build_and_install.sh

# Build only (debug)
xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Debug -quiet

# Build release only
xcodebuild build -project BetterFinder.xcodeproj -scheme BetterFinder -configuration Release -quiet
```

### Dependencies

- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** — terminal emulation library, managed via Swift Package Manager

---

## Architecture

BetterFinder follows **MVVM** (Model-View-ViewModel) architecture:

| Layer | Purpose |
|---|---|
| **Models** | Data types — `FileItem`, `NavigationState`, `SidebarItem`, `WidgetType`, `SortCriteria`, `NetworkItem`, `TerminalTheme` |
| **ViewModels** | Business logic — `FileListViewModel` (file browsing, selection, operations, monitoring, search), `SidebarViewModel` (favorites, volumes) |
| **Services** | System integrations — `FileSystemService`, `NetworkService`, `GitService`, `SystemMonitorService`, `ClipboardService`, `TerminalSession`, `VolumeService`, `KeychainService` |
| **Views** | SwiftUI views organized by feature |
| **Extensions** | Helpers on `URL`, `Date`, `Int64` |

Reactive state management uses Swift's `@Observable` macro. The `ClipboardService` is injected via SwiftUI environment and shared across all panes.

---

## License

All rights reserved.
