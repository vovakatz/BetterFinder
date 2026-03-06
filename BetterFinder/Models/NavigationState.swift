import Foundation

struct NavigationState {
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    private(set) var currentURL: URL

    /// Maps local mount paths (e.g. /Volumes/docker) to network origin (hostname, shareName)
    var networkMounts: [URL: (hostname: String, shareName: String)] = [:]

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = url
    }

    var isNetworkURL: Bool {
        currentURL.scheme == "network"
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var canGoToParent: Bool {
        if isNetworkURL {
            return currentURL.host()?.isEmpty == false
        }
        return currentURL.pathComponents.count > 1
    }

    var parentURL: URL? {
        if isNetworkURL {
            guard canGoToParent else { return nil }
            return URL(string: "network://")!
        }
        // If at the root of a network mount, go back to the network host view
        if let mount = networkMountInfo {
            let mountPath = mount.mountURL.standardizedFileURL.path(percentEncoded: false)
            let currentPath = currentURL.standardizedFileURL.path(percentEncoded: false)
            if currentPath == mountPath {
                return URL(string: "network://\(mount.hostname)")!
            }
        }
        return canGoToParent ? currentURL.deletingLastPathComponent() : nil
    }

    /// Find the network mount info if the current path is inside a mounted network share
    private var networkMountInfo: (mountURL: URL, hostname: String, shareName: String)? {
        let standardized = currentURL.standardizedFileURL
        for (mountURL, info) in networkMounts {
            let mountPath = mountURL.standardizedFileURL.path(percentEncoded: false)
            let currentPath = standardized.path(percentEncoded: false)
            if currentPath == mountPath || currentPath.hasPrefix(mountPath + "/") {
                return (mountURL, info.hostname, info.shareName)
            }
        }
        return nil
    }

    var pathComponents: [(name: String, url: URL)] {
        if isNetworkURL {
            var components: [(name: String, url: URL)] = []
            let rootNetworkURL = URL(string: "network://")!
            components.append((name: "Network", url: rootNetworkURL))
            if let host = currentURL.host(), !host.isEmpty {
                let displayName = host.replacingOccurrences(of: ".local", with: "")
                components.append((name: displayName, url: currentURL))
            }
            return components
        }

        // Check if this path is inside a mounted network share
        if let mount = networkMountInfo {
            var components: [(name: String, url: URL)] = []
            let rootNetworkURL = URL(string: "network://")!
            let hostURL = URL(string: "network://\(mount.hostname)")!
            let displayHost = mount.hostname.replacingOccurrences(of: ".local", with: "")

            components.append((name: "Network", url: rootNetworkURL))
            components.append((name: displayHost, url: hostURL))
            components.append((name: mount.shareName, url: mount.mountURL))

            // Add any subfolders beyond the mount root
            let mountPath = mount.mountURL.standardizedFileURL.path(percentEncoded: false)
            let currentPath = currentURL.standardizedFileURL.path(percentEncoded: false)
            if currentPath != mountPath {
                let suffix = String(currentPath.dropFirst(mountPath.count + 1))
                var buildURL = mount.mountURL
                for part in suffix.components(separatedBy: "/") where !part.isEmpty {
                    buildURL = buildURL.appending(path: part)
                    components.append((name: part, url: buildURL))
                }
            }
            return components
        }

        var components: [(name: String, url: URL)] = []
        var url = currentURL.standardizedFileURL
        while url.pathComponents.count > 1 {
            components.insert((name: url.displayName, url: url), at: 0)
            url = url.deletingLastPathComponent()
        }
        let rootURL = URL(filePath: "/")
        let volumeName = rootURL.displayName
        components.insert((name: volumeName, url: rootURL), at: 0)
        return components
    }

    mutating func navigate(to url: URL) {
        guard url != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
    }

    mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(currentURL)
        currentURL = previous
        return previous
    }

    mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(currentURL)
        currentURL = next
        return next
    }
}
