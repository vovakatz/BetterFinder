import SwiftUI

struct MainContentView: View, Equatable {
    var viewModel: FileListViewModel
    var isActive: Bool = true
    var onActivate: (() -> Void)?

    @State private var showNewFolderSheet = false
    @State private var showNewFileSheet = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel && lhs.isActive == rhs.isActive
    }

    var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 0) {
            ToolbarView(
                pathComponents: vm.pathComponents,
                onNavigate: { viewModel.navigate(to: $0) },
                canGoBack: vm.canGoBack,
                canGoForward: vm.canGoForward,
                onGoBack: { viewModel.goBack() },
                onGoForward: { viewModel.goForward() },
                onNewFolder: { showNewFolderSheet = true },
                onNewFile: { showNewFileSheet = true },
                viewMode: $vm.viewMode,
                showHiddenFiles: $vm.showHiddenFiles,
                onToggleHiddenFiles: {
                    viewModel.toggleHiddenFiles()
                }
            )
            Divider()

            StableFileList(
                viewModel: viewModel,
                showNewFolderSheet: $showNewFolderSheet,
                showNewFileSheet: $showNewFileSheet
            )
        }
        .overlay(alignment: .top) {
            if isActive {
                Color.accentColor
                    .frame(height: 2)
            }
        }
        .background {
            MouseDownDetector { onActivate?() }
        }
    }
}

/// Equatable wrapper that prevents the expensive FileListView from being
/// re-created when unrelated parent state changes (panel toggles, sidebar
/// clicks, etc.).  Only @Observable changes to the ViewModel's data
/// properties (displayItems, isLoading, etc.) trigger body re-evaluation.
/// Selection updates flow through the lazy Binding without re-creating
/// the underlying List.
private struct StableFileList: View, Equatable {
    var viewModel: FileListViewModel
    @Binding var showNewFolderSheet: Bool
    @Binding var showNewFileSheet: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }

    var body: some View {
        // Use untracked getter so the List's internal rendering does NOT
        // register @Observable tracking on selectedItems — preventing
        // a full 5K-row re-render on every selection change.
        let selectionBinding = Binding(
            get: { viewModel.selectedItemsUntracked() },
            set: { viewModel.selectedItems = $0 }
        )

        FileListView(
            displayItems: viewModel.displayItems,
            sortCriteria: viewModel.sortCriteria,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            expandedFolders: viewModel.expandedFolders,
            onSort: { viewModel.toggleSort(by: $0) },
            onOpen: { viewModel.openItem($0) },
            onToggleExpand: { viewModel.toggleExpanded($0) },
            viewMode: viewModel.viewMode,
            onCopy: { viewModel.copyItems($0) },
            onCut: { viewModel.cutItems($0) },
            onPaste: { viewModel.pasteItems() },
            onMoveToTrash: { viewModel.moveToTrash($0) },
            onRequestDelete: { viewModel.requestDelete($0) },
            onConfirmDelete: { viewModel.confirmDelete() },
            onConfirmOverwritePaste: { viewModel.confirmOverwritePaste() },
            canPaste: viewModel.clipboard != nil,
            conflictingNames: viewModel.conflictingNames,
            showOverwriteConfirmation: Binding(
                get: { viewModel.showOverwriteConfirmation },
                set: { viewModel.showOverwriteConfirmation = $0 }
            ),
            needsFullDiskAccess: viewModel.needsFullDiskAccess,
            onOpenFullDiskAccessSettings: { viewModel.openFullDiskAccessSettings() },
            onCreateFolder: { viewModel.createFolder(name: $0) },
            onCreateFile: { viewModel.createFile(name: $0) },
            onRename: { viewModel.renameItem(at: $0, to: $1) },
            showDeleteConfirmation: Binding(
                get: { viewModel.showDeleteConfirmation },
                set: { viewModel.showDeleteConfirmation = $0 }
            ),
            onZip: { viewModel.zipItems($0) },
            onDrop: { urls, isCopy in
                if isCopy {
                    viewModel.requestCopyItems(urls)
                } else {
                    viewModel.requestMoveItems(urls)
                }
            },
            onDropIntoFolder: { urls, folder, isCopy in
                if isCopy {
                    viewModel.requestCopyItems(urls, destination: folder)
                } else {
                    viewModel.requestMoveItems(urls, destination: folder)
                }
            },
            onConfirmMove: { viewModel.confirmMoveItems() },
            pendingMoveNames: viewModel.pendingMoveNames,
            pendingMoveDestinationName: viewModel.pendingMoveDestinationName,
            showMoveConfirmation: Binding(
                get: { viewModel.showMoveConfirmation },
                set: { viewModel.showMoveConfirmation = $0 }
            ),
            onConfirmCopy: { viewModel.confirmCopyItems() },
            pendingCopyNames: viewModel.pendingCopyNames,
            pendingCopyDestinationName: viewModel.pendingCopyDestinationName,
            showCopyConfirmation: Binding(
                get: { viewModel.showCopyConfirmation },
                set: { viewModel.showCopyConfirmation = $0 }
            ),
            showPermissionError: Binding(
                get: { viewModel.showPermissionError },
                set: { viewModel.showPermissionError = $0 }
            ),
            permissionErrorItemName: viewModel.permissionErrorItemName,
            onSkipPermissionItem: { viewModel.skipPermissionItem() },
            onAuthenticatePermissionItem: { viewModel.authenticatePermissionItem() },
            onStopPermissionOperation: { viewModel.stopPermissionOperation() },
            selection: selectionBinding,
            showNewFolderSheet: $showNewFolderSheet,
            showNewFileSheet: $showNewFileSheet
        )
    }
}

private struct MouseDownDetector: NSViewRepresentable {
    var onMouseDown: () -> Void

    func makeNSView(context: Context) -> MouseDownNSView {
        let view = MouseDownNSView()
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: MouseDownNSView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }

    class MouseDownNSView: NSView {
        var onMouseDown: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let locationInView = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locationInView) {
                    self.onMouseDown?()
                }
                return event
            }
        }

        override func removeFromSuperview() {
            removeMonitor()
            super.removeFromSuperview()
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

struct SplitDragHandle: View {
    @Binding var height: CGFloat
    let totalHeight: CGFloat

    @State private var dragStartHeight: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = height
                        }
                        let newHeight = (dragStartHeight ?? height) - value.translation.height
                        height = max(50, min(newHeight, totalHeight - 100))
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
