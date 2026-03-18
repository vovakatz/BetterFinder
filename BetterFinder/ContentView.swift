import SwiftUI

struct FocusedFileListVMKey: FocusedValueKey {
    typealias Value = FileListViewModel
}

extension FocusedValues {
    var activeFileListVM: FileListViewModel? {
        get { self[FocusedFileListVMKey.self] }
        set { self[FocusedFileListVMKey.self] = newValue }
    }
}

struct VerticalDragHandle: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let leadingEdge: Bool

    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let delta = leadingEdge ? value.translation.width : -value.translation.width
                        let newWidth = (dragStartWidth ?? width) + delta
                        width = max(Double(minWidth), min(newWidth, Double(maxWidth)))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct DualPaneDragHandle: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat
    @State private var dragStartFraction: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartFraction == nil {
                            dragStartFraction = fraction
                        }
                        let delta = value.translation.width / totalWidth
                        let newFraction = (dragStartFraction ?? fraction) + delta
                        fraction = max(0.2, min(newFraction, 0.8))
                    }
                    .onEnded { _ in
                        dragStartFraction = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct ContentView: View {
    @State private var fileListVM = FileListViewModel()
    @State private var sidebarVM = SidebarViewModel()
    @State private var sidebarSelection: URL? = FileManager.default.homeDirectoryForCurrentUser
    @AppStorage("showLeftSidebar") private var showLeftSidebar: Bool = true
    @AppStorage("showRightPanel") private var showRightPanel: Bool = true
    @AppStorage("showBottomPanel") private var showBottomPanel: Bool = false
    @State private var searchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @AppStorage("rightTopWidgetRaw") private var rightTopWidgetRaw: String = "Info"
    @AppStorage("rightBottomWidgetRaw") private var rightBottomWidgetRaw: String = "Preview"
    @AppStorage("bottomPanelWidgetRaw") private var bottomPanelWidgetRaw: String = "Terminal"
    @State private var clipboardService = ClipboardService()
    @State private var showDualPane: Bool = false
    @State private var dualPaneSplitFraction: Double = 0.5
    @State private var secondFileListVM = FileListViewModel()
    @State private var activePaneIsSecond: Bool = false
    @State private var bottomPanelHeight: CGFloat?
    @State private var centerPanelHeight: CGFloat = 0
    @AppStorage("leftSidebarWidth") private var leftSidebarWidth: Double = 180
    @AppStorage("rightPanelWidth") private var rightPanelWidth: Double = 220
    @AppStorage("rightPanelSplitFraction") private var rightPanelSplitFraction: Double = 0.5
    @State private var totalWidth: CGFloat = NSScreen.main?.frame.width ?? 1200

    private var effectiveBottomHeight: CGFloat {
        bottomPanelHeight ?? (centerPanelHeight * 0.3)
    }

    private var activeVM: FileListViewModel {
        showDualPane && activePaneIsSecond ? secondFileListVM : fileListVM
    }

    private var rightTopWidgetBinding: Binding<WidgetType> {
        Binding(
            get: { WidgetType(rawValue: rightTopWidgetRaw) ?? .info },
            set: { rightTopWidgetRaw = $0.rawValue }
        )
    }

    private var rightBottomWidgetBinding: Binding<WidgetType> {
        Binding(
            get: { WidgetType(rawValue: rightBottomWidgetRaw) ?? .preview },
            set: { rightBottomWidgetRaw = $0.rawValue }
        )
    }

    private var bottomPanelWidgetBinding: Binding<WidgetType> {
        Binding(
            get: { WidgetType(rawValue: bottomPanelWidgetRaw) ?? .terminal },
            set: { bottomPanelWidgetRaw = $0.rawValue }
        )
    }

    private var rightPanelMaxWidth: CGFloat {
        let sidebarUsed: CGFloat = showLeftSidebar ? CGFloat(leftSidebarWidth) + 5 : 0
        let centerMin: CGFloat = 400
        let handleWidth: CGFloat = 5
        return max(150, totalWidth - sidebarUsed - centerMin - handleWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showLeftSidebar {
                SidebarView(viewModel: sidebarVM, selection: $sidebarSelection)
                    .frame(width: CGFloat(leftSidebarWidth))
                VerticalDragHandle(width: $leftSidebarWidth, minWidth: 100, maxWidth: 300, leadingEdge: true)
            }
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let _ = updateCenterPanelHeight(geo.size.height)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            MainContentView(
                                viewModel: fileListVM,
                                isActive: !activePaneIsSecond || !showDualPane,
                                onActivate: { activePaneIsSecond = false }
                            )
                            .frame(width: showDualPane ? geo.size.width * dualPaneSplitFraction - 2.5 : nil)
                            if showDualPane {
                                DualPaneDragHandle(fraction: $dualPaneSplitFraction, totalWidth: geo.size.width)
                                MainContentView(
                                    viewModel: secondFileListVM,
                                    isActive: activePaneIsSecond,
                                    onActivate: { activePaneIsSecond = true }
                                )
                            }
                        }

                        if showBottomPanel {
                            SplitDragHandle(height: Binding(
                                get: { effectiveBottomHeight },
                                set: { bottomPanelHeight = $0 }
                            ), totalHeight: geo.size.height)

                            BottomPanelView(
                                currentDirectory: activeVM.currentURL,
                                selectedItems: Binding(
                                    get: { activeVM.selectedItems },
                                    set: { activeVM.selectedItems = $0 }
                                ),
                                widgetType: bottomPanelWidgetBinding
                            )
                            .frame(height: effectiveBottomHeight)
                        }
                    }
                }
                Divider()
                StatusBarContainer(viewModel: activeVM)
            }
            .frame(minWidth: 400)
            if showRightPanel {
                VerticalDragHandle(width: $rightPanelWidth, minWidth: 150, maxWidth: rightPanelMaxWidth, leadingEdge: false)
                RightPanelView(
                    selectedItems: Binding(
                        get: { activeVM.selectedItems },
                        set: { activeVM.selectedItems = $0 }
                    ),
                    currentDirectory: activeVM.currentURL,
                    topWidget: rightTopWidgetBinding,
                    bottomWidget: rightBottomWidgetBinding,
                    splitFraction: $rightPanelSplitFraction
                )
                .frame(width: min(CGFloat(rightPanelWidth), rightPanelMaxWidth))
            }
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { totalWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in totalWidth = w }
        })
        .toolbarBackground(Color(red: 0xE5/255.0, green: 0xE5/255.0, blue: 0xE5/255.0), for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showDualPane.toggle()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .foregroundStyle(showDualPane ? Color.accentColor : Color.secondary)
                }
                .help("Dual Pane")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button { showLeftSidebar.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showLeftSidebar ? "Hide left sidebar" : "Show left sidebar")

                Button { showBottomPanel.toggle() } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .help(showBottomPanel ? "Hide bottom panel" : "Show bottom panel")

                Button { showRightPanel.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showRightPanel ? "Hide right panel" : "Show right panel")
                
                Spacer()

                SearchBarView(text: $searchText)
                    .frame(width: 280)
                    .padding(.horizontal, 8)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                activeVM.searchFilter = newValue
            }
        }
        .onChange(of: fileListVM.currentURL) { _, _ in
            if !activePaneIsSecond {
                searchText = ""
                fileListVM.searchFilter = ""
            }
        }
        .onChange(of: secondFileListVM.currentURL) { _, _ in
            if activePaneIsSecond && showDualPane {
                searchText = ""
                secondFileListVM.searchFilter = ""
            }
        }
        .onChange(of: showDualPane) { _, isShowing in
            if isShowing {
                Task { await secondFileListVM.reload() }
            } else {
                activePaneIsSecond = false
            }
        }
        .onChange(of: sidebarSelection) { _, newURL in
            if let url = newURL {
                activeVM.navigate(to: url)
            }
        }
        .environment(clipboardService)
        .focusedSceneValue(\.activeFileListVM, activeVM)
        .task {
            fileListVM.clipboardService = clipboardService
            secondFileListVM.clipboardService = clipboardService
            await fileListVM.reload()
        }
        .sheet(isPresented: $fileListVM.showConnectToServer) {
            ConnectToServerSheet { urlString in
                fileListVM.connectToServer(urlString: urlString)
            }
        }
        .sheet(isPresented: $fileListVM.showAuthSheet) {
            let serverName = fileListVM.pendingAuthHostname
                ?? fileListVM.pendingMountURL?.host()
                ?? "Server"
            AuthenticationSheet(serverName: serverName) { credentials in
                fileListVM.authenticateAndMount(credentials: credentials)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectToServer)) { _ in
            fileListVM.showConnectToServer = true
        }
    }

    private func updateCenterPanelHeight(_ h: CGFloat) {
        if centerPanelHeight != h {
            DispatchQueue.main.async { centerPanelHeight = h }
        }
    }
}

