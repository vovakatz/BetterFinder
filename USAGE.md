# BetterFinder Usage Guide

A complete guide to using every feature in BetterFinder.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Window Layout](#window-layout)
- [Navigating Files](#navigating-files)
- [Browsing Files](#browsing-files)
- [Selecting Files](#selecting-files)
- [File Operations](#file-operations)
- [Search](#search)
- [Sorting](#sorting)
- [Drag and Drop](#drag-and-drop)
- [Sidebar](#sidebar)
- [Network Browsing](#network-browsing)
- [Widgets](#widgets)
  - [Info Widget](#info-widget)
  - [Preview Widget](#preview-widget)
  - [Terminal Widget](#terminal-widget)
  - [Git Widget](#git-widget)
  - [Images Gallery Widget](#images-gallery-widget)
  - [Clipboard Manager Widget](#clipboard-manager-widget)
  - [System Monitor Widget](#system-monitor-widget)
- [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Getting Started

When you first launch BetterFinder, the window opens at a default size of 1000 x 650 points showing your home directory. The interface is divided into three main areas:

- **Left Sidebar** — favorites and mounted volumes
- **Center Area** — the file browser with a toolbar, file list, and optional bottom panel
- **Right Panel** — two stacked widget slots

All panel visibility and sizing preferences are automatically saved and restored between sessions.

---

## Window Layout

### Toggling Panels

Four buttons in the macOS window toolbar control the layout:

| Button | Icon | Action |
|---|---|---|
| Dual Pane | `rectangle.split.2x1` | Splits the center area into two independent file browsers side by side |
| Left Sidebar | `sidebar.left` | Shows or hides the sidebar |
| Bottom Panel | `rectangle.bottomthird.inset.filled` | Shows or hides the bottom widget panel |
| Right Panel | `sidebar.right` | Shows or hides the right widget panel |

The dual pane button is tinted with the accent color when active.

### Resizing Panels

Every panel boundary has a drag handle:

- **Sidebar width** — drag the right edge of the sidebar (range: 100–300 pt)
- **Right panel width** — drag the left edge of the right panel (minimum 150 pt)
- **Bottom panel height** — drag the top edge of the bottom panel (minimum 50 pt)
- **Right panel split** — drag the divider between the top and bottom widget slots (minimum 50 pt per slot)
- **Dual pane split** — drag the divider between the two panes (range: 20%–80%)

All drag handles show a resize cursor when you hover over them. Panel sizes are saved automatically.

### Dual Pane Mode

Click the dual pane button in the toolbar to activate side-by-side file browsing. Each pane operates independently with its own navigation history, selection, search, and view mode.

- **Active pane** — indicated by a 2-point accent-colored bar at the top of the pane. Click anywhere inside a pane to make it active.
- **Menu commands and keyboard shortcuts** always apply to the active pane.
- **Sidebar clicks** navigate the active pane.
- **The search bar** filters the active pane.

When you turn off dual pane mode, the second pane disappears and the first pane remains active.

---

## Navigating Files

### Toolbar Navigation

Each pane has its own navigation toolbar with these controls (left to right):

- **Back button** (chevron left) — go to the previous directory in your navigation history. Disabled when there is no history.
- **Forward button** (chevron right) — go forward after going back. Disabled when there is no forward history.
- **Breadcrumb path bar** — a scrollable row of clickable path components. Each component represents a directory from the volume root to the current location. Click any component to navigate directly to that directory. The current directory is shown in primary color; ancestor directories are in secondary color.

### Other Ways to Navigate

- **Double-click a folder** in the file list to navigate into it.
- **Press Return** with a folder selected to navigate into it.
- **Click a sidebar item** to navigate the active pane to that location.
- **Expand folders inline** by clicking the disclosure triangle (see [Browsing Files](#browsing-files)).

### Network Path Breadcrumbs

When you are browsing inside a mounted network share, the breadcrumb bar shows the network path: **Network > HostName > ShareName > subfolders**. Navigating up from a mounted share's root returns you to the network host view.

---

## Browsing Files

### View Modes

Switch between two view modes using the buttons on the right side of each pane's toolbar:

**List View** (`list.dash` icon):
- Traditional column-based file list with Name, Date Modified, Size, and Kind columns.
- Rows have alternating backgrounds for readability.
- Directories are shown in **bold**. Hidden files appear in gray.
- Directories show "--" in the Size column. Files show human-readable sizes (KB, MB, GB).
- Dates use relative formatting (e.g., "Today 3:42 PM").

**Thumbnail View** (`square.grid.2x2` icon):
- Adaptive grid with QuickLook-generated thumbnails (80 x 80 pt).
- File names appear below thumbnails (up to 2 lines). File size is shown beneath the name.
- Images and documents show rich previews; other files show their system icon.

The active view mode button is tinted with the accent color.

### Inline Folder Expansion (List View)

In list view, local directories show a disclosure triangle on the left side of their row. Click the triangle to expand the folder inline — its contents appear as indented child rows beneath it without navigating away from the current directory. Click the triangle again to collapse it. The triangle animates a 90-degree rotation when expanded.

Expanded folders are monitored for changes in real time, just like the current directory.

### Hidden Files

Click the eye icon in the pane toolbar to toggle hidden file visibility:
- **Eye icon** (visible) — hidden files are shown; icon is accent-colored
- **Eye-slash icon** (hidden) — hidden files are filtered out

The file list reloads immediately when toggled.

### Column Resizing (List View)

Drag the thin handles between column headers to resize columns. Each column has a minimum width (Name: 150 pt, Date: 60 pt, Size: 40 pt, Kind: 60 pt). Column widths scale proportionally when the pane is narrower than the total column width.

### Real-Time Updates

The file list monitors the current directory (and all expanded subdirectories) for changes. When files are created, deleted, or modified by any application, the list updates automatically within about 200 milliseconds.

### Error States

- **Empty folder** — shows a folder icon and "This folder is empty."
- **Permission error** — shows a warning icon with the error message.
- **Full Disk Access required** (e.g., when browsing Trash) — shows a lock icon with an explanation and an "Open System Settings" button that takes you directly to Privacy & Security > Full Disk Access.

---

## Selecting Files

- **Single click** a row to select it.
- **Cmd+click** to toggle individual items in the selection.
- **Shift+click** to select a range of items.
- **Cmd+A** to select all displayed items.
- **Click the background** (empty area) to deselect all.

In thumbnail view, selected items are highlighted with an accent-colored tint.

The status bar at the bottom of each pane shows the number of selected items and the available space on the current volume.

---

## File Operations

### Opening Files

- **Double-click** a file to open it with its default application.
- **Press Return** with a file selected to open it.
- **Right-click > Open** from the context menu.

### Open With

Right-click a file and choose **Open With** to see a submenu of all applications that can open that file type:

- The default application is listed first, labeled **(Default)**.
- All other compatible applications are listed alphabetically with their icons.
- A **Running** submenu shows all currently running applications.
- **Other...** opens a file picker starting in /Applications so you can choose any app.

This option is only available for files (not directories).

### Creating Files and Folders

Two buttons on the right side of each pane's toolbar:

- **New File** (`doc.badge.plus` icon) — opens a sheet where you type the filename and click **Create** (or press Return).
- **New Folder** (`folder.badge.plus` icon) — opens a sheet where you type the folder name and click **Create** (or press Return).

You can also right-click the background of the file list to access **New Folder...** and **New File...** from the context menu.

Press Escape or click Cancel to dismiss the sheet without creating anything.

### Renaming

There are two ways to start a rename:

1. **Click-pause-click** — select an item, then click on its name again after a brief pause (~500 ms). The name becomes an editable text field.
2. **Right-click > Rename** — immediately activates the rename field.

When the rename field appears:
- The filename stem is automatically selected (the extension is left unselected so you don't accidentally change it).
- Press **Return** to commit the rename.
- Press **Escape** to cancel.
- Clicking on a different item commits the current rename before switching selection.

Rename works in both list and thumbnail views.

### Copy, Cut, and Paste

| Action | Shortcut | Context Menu |
|---|---|---|
| Copy | Cmd+C | Right-click > Copy |
| Cut | Cmd+X | Right-click > Cut |
| Paste | Cmd+V | Right-click > Paste |

- **Copy** adds the selected files to BetterFinder's clipboard (and the system clipboard).
- **Cut** marks files for moving. After a successful paste, the cut files are moved from their original location.
- **Paste** places clipboard contents into the current directory.

**Conflict handling:** If the destination already contains files with the same names, an "Overwrite Existing Items?" alert appears listing the conflicting filenames. Choose **Overwrite** to replace them or **Cancel** to abort.

The Paste option in the context menu is disabled when the clipboard is empty.

### Copy Path / Reference

Right-click a file and choose **Copy Path/Reference** for these options:

- **Item Name** — copies just the filename (e.g., `report.pdf`)
- **Path from Root** — copies the absolute path (e.g., `/Users/you/Documents/report.pdf`)
- **Path from Home Dir** — copies a home-relative path (e.g., `~/Documents/report.pdf`). This option is disabled if the file is not located under your home directory.

### Move to Trash

- **Cmd+Delete** or right-click > **Move to Trash**
- This is a reversible operation — items go to the macOS Trash and can be recovered.

### Permanent Delete

- Right-click > **Delete...**
- A confirmation alert appears: *"This will permanently delete the selected item(s). This action cannot be undone."*
- Click **Delete** to confirm or **Cancel** to abort.
- This is irreversible — files are removed immediately.

### Compress (Zip)

- Right-click > **Compress**
- Creates a `.zip` archive in the same directory as the selected items.
- A single item produces an archive named after that item (e.g., `Photos.zip`).
- Multiple items produce an archive named `Archive.zip`.
- If an archive with the same name already exists, the name is auto-incremented (e.g., `Archive 2.zip`, `Archive 3.zip`).
- Resource forks are preserved for single-item compression.

### Show in Finder

- Right-click > **Show in Finder**
- Opens a Finder window with the item highlighted.

---

## Search

The search bar is located in the macOS window toolbar (top of the window). It always applies to the active pane.

### Basic Search

Type any text to filter the file list. The search is case-insensitive and matches anywhere in the filename. Input is debounced by 250 ms to avoid flickering during typing.

### Glob Patterns

Use wildcard characters for more precise filtering:

- `*` matches any number of characters (e.g., `*.pdf` finds all PDF files)
- `?` matches exactly one character (e.g., `file?.txt` matches `file1.txt` but not `file12.txt`)

When wildcards are present, the pattern is matched against the full filename (anchored match). Without wildcards, the text is treated as a substring search.

### Clearing Search

- Click the **X** button that appears on the right side of the search bar.
- Search is also automatically cleared whenever you navigate to a new directory.

---

## Sorting

### Changing the Sort Order (List View)

Click any column header to sort by that field:

| Column | Sort Behavior |
|---|---|
| **Name** | Alphabetical (natural sort, locale-aware) |
| **Date Modified** | Chronological |
| **Size** | Numeric by file size in bytes |
| **Kind** | Alphabetical by file type description |

Click the same column header again to reverse the sort direction. The active sort column shows an arrow indicator — up arrow for ascending, down arrow for descending.

Directories are always sorted before files, regardless of the sort field.

---

## Drag and Drop

### Dragging Files

Click and drag any file or folder from the file list. A preview pill showing the file icon and name follows your cursor.

### Dropping onto a Folder

Drag a file over a folder row — the folder highlights with a gray overlay. Drop the file to move it into that folder.

### Dropping onto the Pane Background

Drop files onto the empty area of a pane to move them into the current directory.

### Copy vs. Move

- **Default** (no modifier) — dropping triggers a **Move** operation.
- **Hold Cmd** while dropping — triggers a **Copy** operation.

Both operations show a confirmation alert listing the items and destination before proceeding.

### Drag to Add Sidebar Favorites

You can drag folders from the file list onto the Favorites section of the sidebar to add them as favorites (see [Sidebar](#sidebar)).

---

## Sidebar

The left sidebar has two sections: **Favorites** and **Locations**.

### Favorites

Default favorites included out of the box:
- Home
- Desktop
- Documents
- Downloads
- Applications
- Trash

**Click** any favorite to navigate the active pane to that location.

**Adding favorites:** Drag a folder from the file list and drop it onto the Favorites section. The folder is inserted at the drop position.

**Reordering favorites:** Drag favorites within the list to rearrange them.

**Removing favorites:** Right-click a custom favorite and select **Remove**. Built-in default favorites cannot be removed (the Remove option is disabled for them).

Favorites are saved to UserDefaults and persist across app sessions.

### Locations

**Network** — click to browse discovered network hosts (see [Network Browsing](#network-browsing)).

**Local Volumes** — all mounted local and external drives are listed automatically. The list updates in real time when drives are mounted or unmounted.

**Network Volumes** — mounted remote volumes (SMB/AFP) appear here with an **Eject** button. Hover over a network volume to reveal the eject button (a circle with an eject icon). Click it to unmount and eject the volume.

---

## Network Browsing

### Discovering Network Hosts

1. Click **Network** in the sidebar's Locations section.
2. BetterFinder automatically discovers hosts on your local network using Bonjour (both SMB and AFP services).
3. After a brief discovery period (~1.5 seconds), available hosts appear as items with a computer icon.

### Browsing Shares

1. Double-click a discovered host (or select it and press Return).
2. BetterFinder queries the host for available SMB shares.
3. If the host requires authentication, an **Authentication Required** sheet appears (see below).
4. Available shares are listed as items with a drive icon.

### Mounting a Share

1. Double-click a share to mount it.
2. If credentials are saved in your Keychain, they are used automatically.
3. If authentication is needed, the Authentication sheet appears.
4. Once mounted, you are navigated directly into the share's directory under `/Volumes/`.

### Authentication Sheet

When a network host or share requires credentials:

- **Username** field — auto-focused; pre-filled from Keychain if credentials were previously saved.
- **Password** field — press Return to connect; pre-filled from Keychain if available.
- **"Remember this password in my keychain"** toggle — when enabled, your credentials are saved to the macOS Keychain for future connections.
- **Guest** button — connects with guest credentials (no password). Use this for shares that allow anonymous access.
- **Cancel** button (or press Escape) — dismisses without connecting.
- **Connect** button (or press Return) — connects with the entered credentials. Disabled if the username is empty.

### Connect to Server (Manual)

For connecting to a specific server address:

1. Press **Cmd+K** or go to **File > Connect to Server...**
2. Enter a server URL (e.g., `smb://192.168.1.100/SharedFolder` or `afp://server.local`).
3. Click **Connect** (or press Return).

**Recent Servers:** Previously connected server addresses are listed below the URL field. Click any recent server to fill in its address. Up to 10 recent servers are remembered.

### Ejecting Network Volumes

Mounted network volumes appear in the sidebar under Locations. Hover over a network volume to reveal the eject button, then click it to unmount.

---

## Widgets

BetterFinder includes seven swappable widget panels. Widgets can be placed in three slots:

- **Right panel top slot** (default: Info)
- **Right panel bottom slot** (default: Preview)
- **Bottom panel** (default: Terminal)

### Switching Widgets

Each widget slot has a header bar with the widget name displayed as a dropdown menu in the center. Click the name to open a dropdown and select a different widget. Available widgets:

- Info
- Preview
- Terminal
- Images
- Git
- Clipboard
- System Monitor

Widget selections are saved and restored between sessions.

---

### Info Widget

Displays comprehensive metadata for the currently selected file.

**When no file is selected:** Shows "No Selection."
**When multiple files are selected:** Shows the count (e.g., "3 items selected").
**When one file is selected:** Shows a scrollable panel with the following sections:

**Basic Info:**
- Name, Kind (e.g., "PDF Document"), UTI identifier
- Size — for files: logical size, data bytes, and physical (allocated) bytes. For directories: a **Calculate** button that recursively computes the total size (runs in the background with a spinner).

**Image Metadata** (for image files only):
- Dimensions (width x height in pixels)
- Color model, color profile, bit depth, alpha channel, DPI
- EXIF data: camera make and model, lens, exposure time, aperture (f-number), ISO, focal length (with 35mm equivalent), flash status, white balance, metering mode, exposure program, exposure bias, date taken
- GPS coordinates: latitude, longitude, altitude

**Dates:**
- Created, Modified, Last Opened, Added to directory

**Permissions:**
- Attributes: Hidden, Readable, Writable, Executable
- Owner, Group, POSIX permissions in symbolic (rwxr-xr-x) and octal (755) notation
- Default application

**Path and Volume:**
- Full file path
- Volume name, total capacity, free space, filesystem format, mount point, device path

All text values in the Info widget support text selection for easy copying.

---

### Preview Widget

Previews the selected file inline within the widget.

**Supported file types:**

| Type | Preview Behavior |
|---|---|
| Images | Displayed with aspect-fit scaling |
| PDFs | Rendered via PDFKit in continuous single-page mode with auto-scaling |
| Text files (including source code, JSON, XML, etc.) | Shown in an editable monospaced text editor |
| Other files | Attempts UTF-8 text rendering; shows "Preview not available" if not decodable |

**Text Editing:**
- Text files are displayed in a fully editable text editor with a monospaced font.
- A **Save** button appears in the widget header. It turns accent-colored when you have unsaved changes.
- Click **Save** to write your changes back to the file.
- Files larger than 100 KB display a "File too large to edit" message instead.
- Unsaved changes are lost when you select a different file.

---

### Terminal Widget

A full terminal emulator embedded in BetterFinder, powered by SwiftTerm.

**The terminal runs `/bin/zsh`** as a login shell, starting in the current pane's directory.

**Controls in the widget header:**

| Control | Location | Description |
|---|---|---|
| **Auto Sync** checkbox | Left side | When enabled, the terminal automatically runs `cd` to match the file browser's current directory whenever you navigate. Toggling it on immediately syncs to the current directory. |
| **Theme picker** (palette icon) | Left side | Opens a dropdown of 9 built-in color themes. The active theme has a checkmark. Selecting a theme applies it immediately. |
| **Clear** (trash icon) | Right side | Clears the terminal screen. |

**Available themes:** Default, 12-bit Rainbow, Aardvark Blue, Adventure, Adventure Time, Belafonte Night, Chester, Cutie Pro, Flat.

The selected theme is saved and restored between sessions. The terminal session is stopped when the widget is hidden or removed.

---

### Git Widget

Provides a complete Git interface for the current directory's repository.

**When outside a git repository:** Shows "Not a Git Repository."

**When inside a git repository:**

**Branch Info:**
- Current branch name displayed in monospaced font.
- Ahead count (orange, e.g., "3↑") — commits that haven't been pushed.
- Behind count (blue, e.g., "2↓") — commits on the remote not yet pulled.

**Changes Section:**
- Lists all modified, added, deleted, renamed, untracked, and conflicted files.
- Each file shows a color-coded status badge:
  - **M** (orange) — Modified
  - **A** (green) — Added
  - **D** (red) — Deleted
  - **R** (blue) — Renamed
  - **?** (gray) — Untracked
  - **U** (purple) — Conflicted
- **Per-file buttons:**
  - Green **+** button — stages the file
  - Orange **-** button — unstages the file
- **Stage All** button — stages all unstaged files (disabled when nothing to stage)
- **Unstage All** button — unstages all staged files (disabled when nothing to unstage)

**Commit Section:**
- Text field for the commit message.
- **Commit (N)** button — creates a commit with the staged files. The number shows how many files are staged. Disabled if no files are staged or the message is empty.
- **Push** button — pushes to the remote. Shows the number of unpushed commits (e.g., "Push (3)"). Disabled when there are no commits to push. Shows a spinner while pushing. Only visible when the branch tracks a remote.

**Recent Commits:**
- Shows the last 20 commits.
- Each commit displays: short hash, commit message, author name, and relative date (e.g., "3 min. ago").

Click the **refresh button** (circular arrow) in the widget header to manually refresh all git information.

---

### Images Gallery Widget

Displays all image files in the current directory as a browsable grid.

- Images are shown in an adaptive grid with QuickLook-generated thumbnails.
- Filenames appear beneath each thumbnail.
- **Single click** an image to select it in the file browser (the Info and Preview widgets update accordingly).
- **Double-click** an image to open it in its default application.
- Images are sorted alphabetically by filename.
- If no images are found in the current directory, shows "No images in this folder."

The gallery refreshes automatically when you navigate to a different directory.

---

### Clipboard Manager Widget

Tracks all copy and cut operations performed during your session.

**Entry Display:**
- Each entry shows a colored badge: **CUT** (orange) or **COPY** (blue).
- Item count and up to 3 filenames are shown per entry. If more than 3 files, shows "+ N more."
- A relative timestamp shows when the operation was performed.

**Sections:**
- **CURRENT** — the active clipboard entry, highlighted with an accent-colored background.
- **HISTORY** — all previous clipboard entries.

**Actions:**
- **Restore** button (circular arrow, on history entries) — makes a past entry the active clipboard again and syncs it to the system clipboard.
- **Remove** button (X circle) — deletes the entry from history.
- **Clear History** (trash icon in widget header) — removes all clipboard entries.

The clipboard manager holds up to 50 entries per session. All copy/cut operations sync with the macOS system pasteboard, so you can paste in other applications too.

---

### System Monitor Widget

Real-time system metrics displayed in a scrollable panel.

**Refresh Interval:**
Click the clock icon in the widget header to choose the update frequency: **0.5s**, **1s**, **2s**, or **5s**. The active interval has a checkmark.

**Metrics displayed:**

| Section | Metrics |
|---|---|
| **CPU** | Usage bar (color-coded: green < 50%, orange 50–80%, red > 80%), total/user/system percentages, process count, load averages (1/5/15 min) |
| **Memory** | Usage bar, used/free/total memory, wired, compressed, swap used |
| **GPU** | Usage bar and percentage (only shown if GPU data is available) |
| **Battery** | Charge bar (red < 20%, orange < 50%, green otherwise), charge %, charging status, time remaining, cycle count (only shown on devices with a battery) |
| **Disk I/O** | Read/write rates (per second), total bytes read/written |
| **Network** | Download/upload rates (per second), total bytes in/out across all network interfaces |
| **System** | Uptime (formatted as Xd Xh Xm), load averages |

Monitoring starts when the widget appears and stops automatically when it is hidden or removed.

---

## Keyboard Shortcuts

### Global Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+C | Copy selected items |
| Cmd+X | Cut selected items |
| Cmd+V | Paste items into current directory |
| Cmd+A | Select all items in the active pane |
| Cmd+Delete | Move selected items to Trash |
| Cmd+K | Connect to Server |
| Return | Open selected item (navigate into folder or open file) |

### In Rename Mode

| Shortcut | Action |
|---|---|
| Return | Commit the rename |
| Escape | Cancel the rename |

### In Sheets (New Folder, New File, Connect to Server, Authentication)

| Shortcut | Action |
|---|---|
| Return | Confirm / Create / Connect |
| Escape | Cancel and dismiss |
