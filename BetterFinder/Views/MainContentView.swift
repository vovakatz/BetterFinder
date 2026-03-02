import SwiftUI

struct MainContentView: View {
    @Bindable var viewModel: FileListViewModel
    var isActive: Bool = true
    var onActivate: (() -> Void)?

    @State private var showNewFolderSheet = false
    @State private var showNewFileSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(
                pathComponents: viewModel.pathComponents,
                onNavigate: { viewModel.navigate(to: $0) },
                canGoBack: viewModel.canGoBack,
                canGoForward: viewModel.canGoForward,
                onGoBack: { viewModel.goBack() },
                onGoForward: { viewModel.goForward() },
                onNewFolder: { showNewFolderSheet = true },
                onNewFile: { showNewFileSheet = true },
                viewMode: $viewModel.viewMode,
                showHiddenFiles: $viewModel.showHiddenFiles,
                onToggleHiddenFiles: {
                    viewModel.showHiddenFiles.toggle()
                    Task { await viewModel.reload() }
                }
            )
            Divider()

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
                showOverwriteConfirmation: $viewModel.showOverwriteConfirmation,
                needsFullDiskAccess: viewModel.needsFullDiskAccess,
                onOpenFullDiskAccessSettings: { viewModel.openFullDiskAccessSettings() },
                onCreateFolder: { viewModel.createFolder(name: $0) },
                onCreateFile: { viewModel.createFile(name: $0) },
                onRename: { viewModel.renameItem(at: $0, to: $1) },
                showDeleteConfirmation: $viewModel.showDeleteConfirmation,
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
                showMoveConfirmation: $viewModel.showMoveConfirmation,
                onConfirmCopy: { viewModel.confirmCopyItems() },
                pendingCopyNames: viewModel.pendingCopyNames,
                pendingCopyDestinationName: viewModel.pendingCopyDestinationName,
                showCopyConfirmation: $viewModel.showCopyConfirmation,
                selection: $viewModel.selectedItems,
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
