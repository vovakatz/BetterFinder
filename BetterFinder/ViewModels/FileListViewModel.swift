import Foundation
import AppKit

enum ViewMode {
    case list
    case thumbnails
}

struct DisplayItem: Identifiable {
    let fileItem: FileItem
    let depth: Int
    var id: URL { fileItem.id }
}

@Observable
final class FileListViewModel {
    private let fileSystemService = FileSystemService()
    let networkService = NetworkService()

    private(set) var navigationState: NavigationState
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var needsFullDiskAccess = false
    var sortCriteria = SortCriteria()
    var showHiddenFiles = false
    var expandedFolders: Set<URL> = []
    var childItems: [URL: [FileItem]] = [:]
    var selectedItems: Set<URL> = []
    var viewMode: ViewMode = .list
    var searchFilter: String = ""

    // Clipboard & delete state
    var clipboardService: ClipboardService?
    var clipboard: (urls: Set<URL>, isCut: Bool)? {
        guard let entry = clipboardService?.current else { return nil }
        return (urls: entry.urls, isCut: entry.isCut)
    }
    var showDeleteConfirmation = false
    var itemsToDelete: Set<URL> = []
    var showOverwriteConfirmation = false
    var conflictingNames: [String] = []

    // Move (drop) state
    var showMoveConfirmation = false
    var pendingMoveURLs: [URL] = []
    var pendingMoveDestination: URL?
    var pendingMoveNames: [String] { pendingMoveURLs.map { $0.lastPathComponent } }
    var pendingMoveDestinationName: String { (pendingMoveDestination ?? currentURL).lastPathComponent }

    // Copy (drop with Cmd) state
    var showCopyConfirmation = false
    var pendingCopyURLs: [URL] = []
    var pendingCopyDestination: URL?
    var pendingCopyNames: [String] { pendingCopyURLs.map { $0.lastPathComponent } }
    var pendingCopyDestinationName: String { (pendingCopyDestination ?? currentURL).lastPathComponent }

    // Network auth state
    var showAuthSheet = false
    var pendingMountURL: URL?
    var pendingAuthHostname: String?  // non-nil when auth is for share enumeration
    var showConnectToServer = false
    private var storedCredentials: [String: NetworkCredentials] = [:]  // hostname -> creds
    private var directoryMonitors: [URL: DispatchSourceFileSystemObject] = [:]
    private var refreshDebounceTask: Task<Void, Never>?

    var volumeStatusText: String {
        if navigationState.isNetworkURL { return "" }
        do {
            let values = try currentURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            if let available = values.volumeAvailableCapacityForImportantUsage,
               let total = values.volumeTotalCapacity {
                let availStr = available.formattedFileSize
                let totalStr = Int64(total).formattedFileSize
                return "\(availStr) of \(totalStr) available"
            }
        } catch {}
        return ""
    }

    var displayItems: [DisplayItem] {
        let filtered = searchFilter.isEmpty ? items : items.filter { matchesSearch($0.name) }
        var result: [DisplayItem] = []
        func addItems(_ items: [FileItem], depth: Int) {
            for item in items {
                result.append(DisplayItem(fileItem: item, depth: depth))
                if item.isDirectory, expandedFolders.contains(item.url),
                   let children = childItems[item.url] {
                    let filteredChildren = searchFilter.isEmpty ? children : children.filter { matchesSearch($0.name) }
                    addItems(filteredChildren, depth: depth + 1)
                }
            }
        }
        addItems(filtered, depth: 0)
        return result
    }

    private func matchesSearch(_ name: String) -> Bool {
        let pattern = searchFilter.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return true }

        // Convert glob pattern to regex:
        // - If no wildcards present, treat as *pattern* (substring match)
        // - Otherwise, anchor the glob pattern
        let hasWildcard = pattern.contains("*") || pattern.contains("?")
        let glob = hasWildcard ? pattern : "*\(pattern)*"

        // Convert glob to regex: escape regex-special chars, then replace glob wildcards
        var regex = NSRegularExpression.escapedPattern(for: glob)
        regex = regex.replacingOccurrences(of: "\\*", with: ".*")
        regex = regex.replacingOccurrences(of: "\\?", with: ".")
        regex = "^" + regex + "$"

        guard let re = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
            // Fallback: simple case-insensitive contains
            return name.localizedCaseInsensitiveContains(pattern)
        }
        return re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    var currentURL: URL { navigationState.currentURL }
    var canGoBack: Bool { navigationState.canGoBack }
    var canGoForward: Bool { navigationState.canGoForward }
    var canGoToParent: Bool { navigationState.canGoToParent }

    var pathComponents: [(name: String, url: URL)] {
        navigationState.pathComponents
    }

    var directoryTitle: String {
        if navigationState.isNetworkURL {
            if let host = currentURL.host(), !host.isEmpty {
                return host.replacingOccurrences(of: ".local", with: "")
            }
            return "Network"
        }
        return currentURL.displayName
    }

    init(startURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.navigationState = NavigationState(url: startURL)
    }

    deinit {
        for source in directoryMonitors.values { source.cancel() }
    }

    func navigate(to url: URL) {
        expandedFolders.removeAll()
        childItems.removeAll()
        navigationState.navigate(to: url)
        Task { await reload() }
    }

    func toggleExpanded(_ item: FileItem) {
        if expandedFolders.contains(item.url) {
            expandedFolders.remove(item.url)
        } else {
            expandedFolders.insert(item.url)
            Task { await loadChildren(for: item.url) }
        }
        updateExpandedMonitors()
    }

    private func loadChildren(for url: URL) async {
        let scheme = url.scheme
        if scheme == "network" {
            // Expanding a network host — enumerate its shares
            let host = url.host() ?? ""
            guard !host.isEmpty else { return }
            let creds = storedCredentials[host]
            let result = await networkService.enumerateShares(on: host, credentials: creds)
            switch result {
            case .success:
                childItems[url] = networkService.sharesAsFileItems(for: host)
            case .authRequired:
                // Need auth to list shares — prompt, then retry
                pendingAuthHostname = host
                pendingMountURL = nil
                showAuthSheet = true
                expandedFolders.remove(url)
            case .error:
                expandedFolders.remove(url)
            }
            return
        }

        do {
            let children = try await fileSystemService.loadContents(
                of: url, showHiddenFiles: showHiddenFiles, sortedBy: sortCriteria
            )
            childItems[url] = children
        } catch {
            // Silently fail — folder just won't show children
        }
    }

    func openItem(_ item: FileItem) {
        let scheme = item.url.scheme
        if scheme == "network" {
            navigate(to: item.url)
        } else if scheme == "smb" || scheme == "afp" {
            // Use stored credentials from the enumeration phase if available
            let host = item.url.host() ?? ""
            let creds = storedCredentials[host]
            Task { await attemptMount(item.url, credentials: creds) }
        } else if item.isDirectory {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func goBack() {
        if let _ = navigationState.goBack() {
            Task { await reload() }
        }
    }

    func goForward() {
        if let _ = navigationState.goForward() {
            Task { await reload() }
        }
    }

    func navigateToParent() {
        if let parent = navigationState.parentURL {
            navigate(to: parent)
        }
    }

    func toggleSort(by field: SortField) {
        if sortCriteria.field == field {
            sortCriteria.ascending.toggle()
        } else {
            sortCriteria.field = field
            sortCriteria.ascending = true
        }
        Task { await reload() }
    }

    private static let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

    var isTrash: Bool {
        guard let trashURL = Self.trashURL else { return false }
        return currentURL.standardizedFileURL == trashURL.standardizedFileURL
    }

    func reload() async {
        refreshDebounceTask?.cancel()
        expandedFolders.removeAll()
        childItems.removeAll()
        isLoading = true
        errorMessage = nil
        needsFullDiskAccess = false

        if currentURL.scheme == "network" {
            await reloadNetwork()
        } else {
            await reloadFileSystem()
        }

        isLoading = false
        startMonitoring()
    }

    private func reloadNetwork(credentials: NetworkCredentials? = nil) async {
        let host = currentURL.host() ?? ""
        if host.isEmpty {
            networkService.startDiscovery()
            // Brief delay to let Bonjour discover hosts
            try? await Task.sleep(for: .milliseconds(1500))
            items = networkService.hostsAsFileItems()
        } else {
            let result = await networkService.enumerateShares(on: host, credentials: credentials)
            switch result {
            case .success(let shares):
                // Store credentials for later use when mounting shares on this host
                if let creds = credentials {
                    storedCredentials[host] = creds
                }
                items = networkService.sharesAsFileItems(for: host)
                if shares.isEmpty {
                    errorMessage = "No shares found on \(host)"
                }
            case .authRequired:
                items = []
                pendingAuthHostname = host
                pendingMountURL = nil
                showAuthSheet = true
            case .error(let message):
                items = []
                errorMessage = message
            }
        }
    }

    private func reloadFileSystem() async {
        do {
            let loaded = try await fileSystemService.loadContents(
                of: currentURL,
                showHiddenFiles: showHiddenFiles,
                sortedBy: sortCriteria
            )
            items = loaded
        } catch {
            if isTrash, (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoPermissionError {
                needsFullDiskAccess = true
                errorMessage = "BetterFinder needs Full Disk Access to view the Trash."
            } else {
                errorMessage = error.localizedDescription
            }
            items = []
        }
    }

    // MARK: - Directory Monitoring

    private func startMonitoring() {
        stopAllMonitors()
        guard currentURL.isFileURL else { return }
        addMonitor(for: currentURL)
    }

    func updateExpandedMonitors() {
        let desired = expandedFolders.filter { $0.isFileURL }
        let monitored = Set(directoryMonitors.keys).subtracting([currentURL])

        for url in monitored.subtracting(desired) {
            directoryMonitors[url]?.cancel()
            directoryMonitors[url] = nil
        }
        for url in desired.subtracting(monitored) {
            addMonitor(for: url)
        }
    }

    private func addMonitor(for url: URL) {
        guard directoryMonitors[url] == nil else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.refreshDebounceTask?.cancel()
            self.refreshDebounceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                await self.refreshItems()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitors[url] = source
    }

    private func stopAllMonitors() {
        for source in directoryMonitors.values { source.cancel() }
        directoryMonitors.removeAll()
    }

    private func refreshItems() async {
        guard currentURL.isFileURL else { return }
        do {
            let loaded = try await fileSystemService.loadContents(
                of: currentURL,
                showHiddenFiles: showHiddenFiles,
                sortedBy: sortCriteria
            )
            items = loaded
        } catch {
            // Silently ignore refresh errors
        }
        for url in expandedFolders where url.isFileURL {
            do {
                let children = try await fileSystemService.loadContents(
                    of: url, showHiddenFiles: showHiddenFiles, sortedBy: sortCriteria
                )
                childItems[url] = children
            } catch {
                // Silently ignore
            }
        }
    }

    // MARK: - Network Mounting

    func attemptMount(_ url: URL, credentials: NetworkCredentials? = nil) async {
        let mountPoint = await networkService.mountShare(url: url, credentials: credentials)
        if let mountPoint {
            navigate(to: mountPoint)
        } else {
            pendingMountURL = url
            showAuthSheet = true
        }
    }

    func authenticateAndMount(credentials: NetworkCredentials) {
        if let hostname = pendingAuthHostname {
            // Auth was for share enumeration
            pendingAuthHostname = nil
            Task {
                isLoading = true
                await reloadNetwork(credentials: credentials)
                isLoading = false
            }
        } else if let url = pendingMountURL {
            // Auth was for mounting a share
            pendingMountURL = nil
            Task { await attemptMount(url, credentials: credentials) }
        }
    }

    func connectToServer(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "smb" || url.scheme == "afp" else {
            errorMessage = "Invalid server URL. Use smb:// or afp:// format."
            return
        }
        // Save to recent servers
        var recents = UserDefaults.standard.stringArray(forKey: "recentServers") ?? []
        recents.removeAll { $0 == trimmed }
        recents.insert(trimmed, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        UserDefaults.standard.set(recents, forKey: "recentServers")

        Task { await attemptMount(url) }
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    // MARK: - Rename

    func renameItem(at url: URL, to newName: String) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard newURL != url else { return }
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        Task { await reload() }
    }

    // MARK: - Create operations

    func createFolder(name: String) {
        let folderURL = currentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        Task { await reload() }
    }

    func createFile(name: String) {
        let fileURL = currentURL.appendingPathComponent(name)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
            errorMessage = "Could not create file \"\(name)\"."
        }
        Task { await reload() }
    }

    // MARK: - Clipboard operations

    func copyItems(_ urls: Set<URL>) {
        clipboardService?.setCopy(urls)
    }

    func cutItems(_ urls: Set<URL>) {
        clipboardService?.setCut(urls)
    }

    func pasteItems() {
        guard let clipboard else { return }
        let fm = FileManager.default

        // Check for conflicts
        let conflicts = clipboard.urls.filter { sourceURL in
            let destURL = currentURL.appendingPathComponent(sourceURL.lastPathComponent)
            return fm.fileExists(atPath: destURL.path)
        }

        if !conflicts.isEmpty {
            conflictingNames = conflicts.map { $0.lastPathComponent }.sorted()
            showOverwriteConfirmation = true
            return
        }

        performPaste()
    }

    func confirmOverwritePaste() {
        performPaste(overwrite: true)
    }

    private func performPaste(overwrite: Bool = false) {
        guard let clipboard else { return }
        let fm = FileManager.default
        for sourceURL in clipboard.urls {
            let destURL = currentURL.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if overwrite && fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                if clipboard.isCut {
                    try fm.moveItem(at: sourceURL, to: destURL)
                } else {
                    try fm.copyItem(at: sourceURL, to: destURL)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if clipboard.isCut {
            clipboardService?.clearCurrent()
        }
        Task { await reload() }
    }

    func moveToTrash(_ urls: Set<URL>) {
        let fm = FileManager.default
        for url in urls {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        selectedItems.subtract(urls)
        Task { await reload() }
    }

    func requestDelete(_ urls: Set<URL>) {
        itemsToDelete = urls
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        let fm = FileManager.default
        for url in itemsToDelete {
            do {
                try fm.removeItem(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        selectedItems.subtract(itemsToDelete)
        itemsToDelete.removeAll()
        Task { await reload() }
    }

    // MARK: - Compress (Zip)

    func zipItems(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        let directory = currentURL
        let sortedURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Determine archive name
        let baseName: String
        if sortedURLs.count == 1 {
            baseName = sortedURLs[0].deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }

        // Deduplicate: find a unique name
        let fm = FileManager.default
        var archiveName = "\(baseName).zip"
        var counter = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(archiveName).path) {
            archiveName = "\(baseName) \(counter).zip"
            counter += 1
        }

        let archiveURL = directory.appendingPathComponent(archiveName)

        Task.detached {
            do {
                if sortedURLs.count == 1 {
                    // Single item: use ditto directly
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                         sortedURLs[0].path, archiveURL.path]
                    let errorPipe = Pipe()
                    process.standardError = errorPipe
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        await MainActor.run { self.errorMessage = "Compress failed: \(msg)" }
                    }
                } else {
                    // Multiple items: use /usr/bin/zip from the current directory
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    process.currentDirectoryURL = directory
                    var arguments = ["-r", "-y", archiveURL.path]
                    for url in sortedURLs {
                        arguments.append(url.lastPathComponent)
                    }
                    process.arguments = arguments
                    let errorPipe = Pipe()
                    process.standardError = errorPipe
                    process.standardOutput = Pipe() // suppress output
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        await MainActor.run { self.errorMessage = "Compress failed: \(msg)" }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Compress failed: \(error.localizedDescription)"
                }
            }

            await self.reload()
        }
    }

    // MARK: - Drop/Move operations

    func requestMoveItems(_ urls: [URL], destination: URL? = nil) {
        let dest = destination ?? currentURL
        let toMove = urls.filter {
            $0.deletingLastPathComponent().standardizedFileURL != dest.standardizedFileURL
            && $0.standardizedFileURL != dest.standardizedFileURL
        }
        guard !toMove.isEmpty else { return }
        pendingMoveURLs = toMove
        pendingMoveDestination = dest
        showMoveConfirmation = true
    }

    func confirmMoveItems() {
        let dest = pendingMoveDestination ?? currentURL
        let fm = FileManager.default
        for url in pendingMoveURLs {
            let destURL = dest.appendingPathComponent(url.lastPathComponent)
            do {
                try fm.moveItem(at: url, to: destURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        pendingMoveURLs = []
        pendingMoveDestination = nil
    }

    // MARK: - Drop/Copy operations (Cmd+Drop)

    func requestCopyItems(_ urls: [URL], destination: URL? = nil) {
        let dest = destination ?? currentURL
        let toCopy = urls.filter {
            $0.deletingLastPathComponent().standardizedFileURL != dest.standardizedFileURL
            && $0.standardizedFileURL != dest.standardizedFileURL
        }
        guard !toCopy.isEmpty else { return }
        pendingCopyURLs = toCopy
        pendingCopyDestination = dest
        showCopyConfirmation = true
    }

    func confirmCopyItems() {
        let dest = pendingCopyDestination ?? currentURL
        let fm = FileManager.default
        for url in pendingCopyURLs {
            let destURL = dest.appendingPathComponent(url.lastPathComponent)
            do {
                try fm.copyItem(at: url, to: destURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        pendingCopyURLs = []
        pendingCopyDestination = nil
    }
}
