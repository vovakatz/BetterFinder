import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileListView: View {
    let displayItems: [DisplayItem]
    let sortCriteria: SortCriteria
    let isLoading: Bool
    let errorMessage: String?
    let expandedFolders: Set<URL>
    let onSort: (SortField) -> Void
    let onOpen: (FileItem) -> Void
    let onToggleExpand: (FileItem) -> Void
    var viewMode: ViewMode = .list

    var onCopy: (Set<URL>) -> Void = { _ in }
    var onCut: (Set<URL>) -> Void = { _ in }
    var onPaste: () -> Void = {}
    var onMoveToTrash: (Set<URL>) -> Void = { _ in }
    var onRequestDelete: (Set<URL>) -> Void = { _ in }
    var onConfirmDelete: () -> Void = {}
    var onConfirmOverwritePaste: () -> Void = {}
    var canPaste: Bool = false
    var conflictingNames: [String] = []
    @Binding var showOverwriteConfirmation: Bool
    var needsFullDiskAccess: Bool = false
    var onOpenFullDiskAccessSettings: () -> Void = {}
    var onCreateFolder: (String) -> Void = { _ in }
    var onCreateFile: (String) -> Void = { _ in }
    var onRename: (URL, String) -> Void = { _, _ in }
    @Binding var showDeleteConfirmation: Bool

    var onZip: (Set<URL>) -> Void = { _ in }
    var onDrop: ([URL], Bool) -> Void = { _, _ in }
    var onDropIntoFolder: ([URL], URL, Bool) -> Void = { _, _, _ in }
    var onConfirmMove: () -> Void = {}
    var pendingMoveNames: [String] = []
    var pendingMoveDestinationName: String = ""
    @Binding var showMoveConfirmation: Bool
    var onConfirmCopy: () -> Void = {}
    var pendingCopyNames: [String] = []
    var pendingCopyDestinationName: String = ""
    @Binding var showCopyConfirmation: Bool

    // Permission error
    @Binding var showPermissionError: Bool
    var permissionErrorItemName: String = ""
    var onSkipPermissionItem: () -> Void = {}
    var onAuthenticatePermissionItem: () -> Void = {}
    var onStopPermissionOperation: () -> Void = {}

    var currentFolderURL: URL

    @Binding var selection: Set<FileItem.ID>
    private let terminalLauncher = TerminalLauncherService()
    @State private var dateWidth: CGFloat = 150
    @State private var sizeWidth: CGFloat = 80
    @State private var kindWidth: CGFloat = 120
    @State private var doubleClickProxy = DoubleClickProxy()
    @Binding var showNewFolderSheet: Bool
    @Binding var showNewFileSheet: Bool
    @State private var newItemName = ""
    @State private var renamingURL: URL? = nil
    @State private var renameText = ""

    var body: some View {
        // Capture the Binding (not its value) so closures read current
        // selection at call time — body may not re-evaluate on selection change.
        let selBinding = $selection
        let _ = doubleClickProxy.updateDoubleClickAction { [displayItems, onOpen] in
            doubleClickProxy.cancelPendingRename()
            renamingURL = nil
            let currentSelection = selBinding.wrappedValue
            guard let selectedURL = currentSelection.first,
                  let displayItem = displayItems.first(where: { $0.id == selectedURL }) else { return }
            onOpen(displayItem.fileItem)
        }
        let _ = doubleClickProxy.updateSingleClickAction { [displayItems, doubleClickProxy] in
            let currentSelection = selBinding.wrappedValue
            guard renamingURL == nil,
                  currentSelection.count == 1,
                  let url = currentSelection.first,
                  doubleClickProxy.nameHoverURL == url,
                  let item = displayItems.first(where: { $0.id == url }) else { return }
            doubleClickProxy.schedulePendingRename {
                renamingURL = url
                renameText = item.fileItem.name
            }
        }

        GeometryReader { geo in
            let effWidths = effectiveWidths(for: geo.size.width)

            VStack(spacing: 0) {
                if viewMode == .list {
                    ColumnHeaderView(
                        sortCriteria: sortCriteria,
                        onSort: onSort,
                        dateWidth: $dateWidth,
                        sizeWidth: $sizeWidth,
                        kindWidth: $kindWidth,
                        effectiveDateWidth: effWidths.date,
                        effectiveSizeWidth: effWidths.size,
                        effectiveKindWidth: effWidths.kind
                    )
                    Divider()
                }

                if isLoading {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay { ProgressView() }
                        .onDrop(of: [.fileURL], delegate: PaneDropDelegate(onDrop: onDrop))
                } else if let error = errorMessage {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: needsFullDiskAccess ? "lock.shield" : "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text(error)
                                    .foregroundStyle(.secondary)
                                if needsFullDiskAccess {
                                    Button("Open System Settings") {
                                        onOpenFullDiskAccessSettings()
                                    }
                                }
                            }
                        }
                        .onDrop(of: [.fileURL], delegate: PaneDropDelegate(onDrop: onDrop))
                } else if displayItems.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("This folder is empty")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDrop(of: [.fileURL], delegate: PaneDropDelegate(onDrop: onDrop))
                } else {
                    contentView(effWidths: effWidths)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Delete Permanently?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onConfirmDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the selected item(s). This action cannot be undone.")
            }
            .alert("Overwrite Existing Items?", isPresented: $showOverwriteConfirmation) {
                Button("Overwrite", role: .destructive) {
                    onConfirmOverwritePaste()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let names = conflictingNames.joined(separator: ", ")
                Text("The destination already contains: \(names). Do you want to overwrite?")
            }
            .alert("Move Items?", isPresented: $showMoveConfirmation) {
                Button("Move") { onConfirmMove() }
                Button("Cancel", role: .cancel) {}
            } message: {
                let names = pendingMoveNames.joined(separator: ", ")
                Text("Move \(names) to \"\(pendingMoveDestinationName)\"?")
            }
            .alert("Copy Items?", isPresented: $showCopyConfirmation) {
                Button("Copy") { onConfirmCopy() }
                Button("Cancel", role: .cancel) {}
            } message: {
                let names = pendingCopyNames.joined(separator: ", ")
                Text("Copy \(names) to \"\(pendingCopyDestinationName)\"?")
            }
            .alert("Item is not movable", isPresented: $showPermissionError) {
                Button("Skip") { onSkipPermissionItem() }
                Button("Authenticate") { onAuthenticatePermissionItem() }
                Button("Stop", role: .cancel) { onStopPermissionOperation() }
            } message: {
                Text("You don't have sufficient permissions to move the item \"\(permissionErrorItemName)\".")
            }
            .sheet(isPresented: $showNewFolderSheet) {
                NewItemSheet(title: "New Folder", placeholder: "Folder name") { name in
                    onCreateFolder(name)
                }
            }
            .sheet(isPresented: $showNewFileSheet) {
                NewItemSheet(title: "New File", placeholder: "File name") { name in
                    onCreateFile(name)
                }
            }
            .onAppear { doubleClickProxy.startMonitoring() }
            .onDisappear { doubleClickProxy.stopMonitoring() }
        }
    }

    private func effectiveWidths(for containerWidth: CGFloat) -> (date: CGFloat, size: CGFloat, kind: CGFloat) {
        let nameMinWidth: CGFloat = 150
        let spacers: CGFloat = 24 + 16
        let secondaryTotal = dateWidth + sizeWidth + kindWidth
        let needed = nameMinWidth + secondaryTotal + spacers
        guard containerWidth > 0, containerWidth < needed else {
            return (dateWidth, sizeWidth, kindWidth)
        }
        let available = max(0, containerWidth - nameMinWidth - spacers)
        let scale = available / secondaryTotal
        return (dateWidth * scale, sizeWidth * scale, kindWidth * scale)
    }

    @ViewBuilder
    private func contentView(effWidths: (date: CGFloat, size: CGFloat, kind: CGFloat)) -> some View {
        switch viewMode {
        case .list:
            listView(effWidths: effWidths)
        case .thumbnails:
            thumbnailGridView
        }
    }

    private func listView(effWidths: (date: CGFloat, size: CGFloat, kind: CGFloat)) -> some View {
        let resolveDeferredIcons = displayItems.count <= 400

        return List(displayItems, selection: $selection) { displayItem in
            FileRowView(
                item: displayItem.fileItem,
                dateWidth: effWidths.date,
                sizeWidth: effWidths.size,
                kindWidth: effWidths.kind,
                depth: displayItem.depth,
                isExpanded: expandedFolders.contains(displayItem.fileItem.url),
                onToggleExpand: { onToggleExpand(displayItem.fileItem) },
                isRenaming: renamingURL == displayItem.id,
                resolveDeferredIcon: resolveDeferredIcons,
                renameText: $renameText,
                onCommitRename: { commitRename(for: displayItem.id) },
                onCancelRename: { cancelRename() },
                onNameHover: { hovering in
                    if hovering {
                        doubleClickProxy.nameHoverURL = displayItem.id
                    } else if doubleClickProxy.nameHoverURL == displayItem.id {
                        doubleClickProxy.nameHoverURL = nil
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            .draggable(displayItem.fileItem.url) {
                FileDragPreview(item: displayItem.fileItem)
            }
            .itemDropDestination(item: displayItem, onDropIntoFolder: onDropIntoFolder, onDrop: onDrop)
            .tag(displayItem.id)
        }
        .listStyle(.plain)
        .alternatingRowBackgrounds()
        .environment(\.defaultMinListRowHeight, 20)
        .paneDropTarget(onDrop: onDrop)
        .onHover { doubleClickProxy.isHovered = $0 }
        .onKeyPress(.return) {
            if renamingURL != nil {
                return .ignored // let TextField handle it
            }
            openSelected()
            return .handled
        }
        .onCopyCommand {
            guard !selection.isEmpty else { return [] }
            onCopy(selection)
            return selection.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onCutCommand {
            guard !selection.isEmpty else { return [] }
            onCut(selection)
            return selection.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onPasteCommand(of: [.fileURL]) { _ in
            onPaste()
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { selectedIDs in
            if selectedIDs.isEmpty {
                backgroundContextMenu
            } else {
                contextMenuContent(forSelection: selectedIDs)
            }
        }
        .onChange(of: selection) { _, newValue in
            doubleClickProxy.cancelPendingRename()
            if let renaming = renamingURL, !newValue.contains(renaming) {
                commitRename(for: renaming)
            }
        }
    }

    private var thumbnailGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120))],
                spacing: 8
            ) {
                ForEach(displayItems) { displayItem in
                    FileThumbnailView(
                        item: displayItem.fileItem,
                        isSelected: selection.contains(displayItem.id),
                        isRenaming: renamingURL == displayItem.id,
                        renameText: $renameText,
                        onCommitRename: { commitRename(for: displayItem.id) },
                        onCancelRename: { cancelRename() }
                    )
                    .onTapGesture {
                        selection = [displayItem.id]
                    }
                    .draggable(displayItem.fileItem.url) {
                        FileDragPreview(item: displayItem.fileItem)
                    }
                    .itemDropDestination(item: displayItem, onDropIntoFolder: onDropIntoFolder, onDrop: onDrop)
                    .tag(displayItem.id)
                    .contextMenu {
                        let targets: Set<FileItem.ID> = selection.contains(displayItem.id) ? selection : [displayItem.id]
                        contextMenuContent(forSelection: targets)
                    }
                }
            }
            .padding(8)
        }
        .paneDropTarget(onDrop: onDrop)
        .onHover { doubleClickProxy.isHovered = $0 }
        .onKeyPress(.return) {
            if renamingURL != nil {
                return .ignored
            }
            openSelected()
            return .handled
        }
        .onCopyCommand {
            guard !selection.isEmpty else { return [] }
            onCopy(selection)
            return selection.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onCutCommand {
            guard !selection.isEmpty else { return [] }
            onCut(selection)
            return selection.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onPasteCommand(of: [.fileURL]) { _ in
            onPaste()
        }
        .contextMenu { backgroundContextMenu }
        .onChange(of: selection) { _, newValue in
            doubleClickProxy.cancelPendingRename()
            if let renaming = renamingURL, !newValue.contains(renaming) {
                commitRename(for: renaming)
            }
        }
    }

    @ViewBuilder
    private var backgroundContextMenu: some View {
        Button("New Folder...") {
            newItemName = ""
            showNewFolderSheet = true
        }
        Button("New File...") {
            newItemName = ""
            showNewFileSheet = true
        }
        if !isNetworkContext {
            Divider()
            Button("Open in Terminal") {
                terminalLauncher.openTerminal(at: currentFolderURL)
            }
        }
        if canPaste {
            Divider()
            Button("Paste") {
                onPaste()
            }
            .keyboardShortcut("v", modifiers: .command)
        }
    }

    private var isNetworkContext: Bool {
        let scheme = displayItems.first?.fileItem.url.scheme
        return scheme == "network" || scheme == "smb" || scheme == "afp"
    }

    @ViewBuilder
    private func contextMenuContent(forSelection selectedIDs: Set<FileItem.ID>) -> some View {
        let targetURLs = selectedIDs
        let selectedItems = displayItems.filter { selectedIDs.contains($0.id) }
        let primaryItem = selectedItems.first?.fileItem
        let scheme = primaryItem?.url.scheme
        let isSingle = selectedIDs.count == 1

        Button("Open") {
            selection = targetURLs
            for displayItem in selectedItems {
                onOpen(displayItem.fileItem)
            }
        }

        if scheme != "network" && scheme != "smb" && scheme != "afp" {
            let hasOpenable = selectedItems.contains {
                !$0.fileItem.isDirectory || $0.fileItem.isPackage
            }
            if hasOpenable {
                Button("Open With...") {
                    selection = targetURLs
                    chooseAppAndOpen(Array(targetURLs))
                }
            }

            Button("Show in Finder") {
                selection = targetURLs
                NSWorkspace.shared.activateFileViewerSelecting(Array(targetURLs))
            }

            if isSingle, let item = primaryItem {
                Button("Open in Terminal") {
                    if item.isDirectory && !item.isPackage {
                        terminalLauncher.openTerminal(at: item.url)
                    } else {
                        terminalLauncher.openTerminal(
                            at: item.url.deletingLastPathComponent(),
                            prefilledFilename: item.url.lastPathComponent
                        )
                    }
                }

                Menu("Copy Path/Reference") {
                    Button("Item Name") {
                        copyToPasteboard(item.name)
                    }
                    Button("Path from Root") {
                        copyToPasteboard(item.url.path(percentEncoded: false))
                    }
                    let fullPath = item.url.path(percentEncoded: false)
                    let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
                    let isUnderHome = fullPath.hasPrefix(homePath)
                    Button("Path from Home Dir") {
                        let relative = String(fullPath.dropFirst(homePath.count))
                        let trimmed = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
                        copyToPasteboard("~/\(trimmed)")
                    }
                    .disabled(!isUnderHome)
                }

                Divider()

                Button("Rename") {
                    selection = [item.url]
                    renamingURL = item.url
                    renameText = item.name
                }
            }

            Divider()

            Button("Cut") {
                selection = targetURLs
                onCut(targetURLs)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                selection = targetURLs
                onCopy(targetURLs)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                onPaste()
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!canPaste)

            Divider()

            Button("Move to Trash") {
                selection = targetURLs
                onMoveToTrash(targetURLs)
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Button("Delete...", role: .destructive) {
                selection = targetURLs
                onRequestDelete(targetURLs)
            }

            Divider()

            Button("Compress") {
                selection = targetURLs
                onZip(targetURLs)
            }
        }
    }

    private func openFiles(_ urls: [URL], withApp appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }

    private func chooseAppAndOpen(_ urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.begin { response in
            if response == .OK, let appURL = panel.url {
                openFiles(urls, withApp: appURL)
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func commitRename(for url: URL) {
        guard renamingURL != nil else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(url, trimmed)
        }
        renamingURL = nil
        renameText = ""
    }

    private func cancelRename() {
        renamingURL = nil
        renameText = ""
    }

    private func openSelected() {
        guard let selectedURL = selection.first,
              let displayItem = displayItems.first(where: { $0.id == selectedURL }) else { return }
        onOpen(displayItem.fileItem)
    }
}

private struct NewItemSheet: View {
    let title: String
    let placeholder: String
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !name.isEmpty {
                        onCreate(name)
                        dismiss()
                    }
                }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    onCreate(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { isFocused = true }
    }
}

private class DoubleClickProxy {
    var onDoubleClick: (() -> Void)?
    var onSingleClick: (() -> Void)?
    var isHovered = false
    var monitor: Any?
    var pendingRenameWork: DispatchWorkItem?
    var nameHoverURL: URL?

    func updateDoubleClickAction(_ action: @escaping () -> Void) {
        onDoubleClick = action
    }

    func updateSingleClickAction(_ action: @escaping () -> Void) {
        onSingleClick = action
    }

    func schedulePendingRename(_ action: @escaping () -> Void) {
        pendingRenameWork?.cancel()
        let work = DispatchWorkItem(block: action)
        pendingRenameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func cancelPendingRename() {
        pendingRenameWork?.cancel()
        pendingRenameWork = nil
    }

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self, self.isHovered else { return event }
            if event.type == .leftMouseDragged {
                self.cancelPendingRename()
                return event
            }
            // Ignore clicks that are reactivating the window (e.g. switching back from another app)
            guard event.window?.isKeyWindow == true else { return event }
            if event.clickCount == 2 {
                self.cancelPendingRename()
                self.onDoubleClick?()
            } else if event.clickCount == 1 {
                self.cancelPendingRename()
                self.onSingleClick?()
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

private struct FileDragPreview: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 6) {
            FileItemIconView(item: item, resolveDeferredIcon: false)
                .frame(width: 16, height: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background)
        .cornerRadius(4)
    }
}

private struct PaneDropDelegate: DropDelegate {
    let onDrop: ([URL], Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: NSEvent.modifierFlags.contains(.command) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let isCopy = NSEvent.modifierFlags.contains(.command)
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { cont in
                    _ = provider.loadObject(ofClass: NSURL.self) { reading, _ in
                        cont.resume(returning: reading as? URL)
                    }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty {
                await MainActor.run { onDrop(urls, isCopy) }
            }
        }
        return true
    }
}

private struct FolderDropDelegate: DropDelegate {
    let folderURL: URL
    let onDropIntoFolder: ([URL], URL, Bool) -> Void
    @Binding var isTargeted: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: NSEvent.modifierFlags.contains(.command) ? .copy : .move)
    }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        let isCopy = NSEvent.modifierFlags.contains(.command)
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { cont in
                    _ = provider.loadObject(ofClass: NSURL.self) { reading, _ in
                        cont.resume(returning: reading as? URL)
                    }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty {
                await MainActor.run { onDropIntoFolder(urls, folderURL, isCopy) }
            }
        }
        return true
    }
}

private struct FolderDropModifier: ViewModifier {
    let folderURL: URL
    let onDropIntoFolder: ([URL], URL, Bool) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.gray.opacity(0.35) : Color.clear)
            .onDrop(of: [.fileURL], delegate: FolderDropDelegate(
                folderURL: folderURL,
                onDropIntoFolder: onDropIntoFolder,
                isTargeted: $isTargeted
            ))
    }
}

private extension View {
    @ViewBuilder
    func itemDropDestination(
        item: DisplayItem,
        onDropIntoFolder: @escaping ([URL], URL, Bool) -> Void,
        onDrop: @escaping ([URL], Bool) -> Void
    ) -> some View {
        if item.fileItem.isDirectory {
            self.modifier(FolderDropModifier(
                folderURL: item.fileItem.url,
                onDropIntoFolder: onDropIntoFolder
            ))
        } else {
            self.onDrop(of: [.fileURL], delegate: PaneDropDelegate(onDrop: onDrop))
        }
    }

    func paneDropTarget(onDrop: @escaping ([URL], Bool) -> Void) -> some View {
        self.onDrop(of: [.fileURL], delegate: PaneDropDelegate(onDrop: onDrop))
    }
}
