import Foundation
import Network
import AppKit

@Observable
final class NetworkService {
    private(set) var discoveredHosts: [NetworkHost] = []
    private(set) var shares: [String: [NetworkShare]] = [:]

    private var smbBrowser: NWBrowser?
    private var afpBrowser: NWBrowser?
    private var isDiscovering = false

    // MARK: - Discovery

    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        discoveredHosts = []

        let smbDescriptor = NWBrowser.Descriptor.bonjour(type: "_smb._tcp.", domain: nil)
        let afpDescriptor = NWBrowser.Descriptor.bonjour(type: "_afpovertcp._tcp.", domain: nil)

        smbBrowser = createBrowser(descriptor: smbDescriptor, serviceType: .smb)
        afpBrowser = createBrowser(descriptor: afpDescriptor, serviceType: .afp)

        smbBrowser?.start(queue: .main)
        afpBrowser?.start(queue: .main)
    }

    func stopDiscovery() {
        smbBrowser?.cancel()
        afpBrowser?.cancel()
        smbBrowser = nil
        afpBrowser = nil
        isDiscovering = false
    }

    private func createBrowser(descriptor: NWBrowser.Descriptor, serviceType: NetworkServiceType) -> NWBrowser {
        let params = NWParameters()
        let browser = NWBrowser(for: descriptor, using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.mergeResults(results, serviceType: serviceType)
        }
        return browser
    }

    private func mergeResults(_ results: Set<NWBrowser.Result>, serviceType: NetworkServiceType) {
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }

            let hostname = "\(name).local"
            let id = hostname.lowercased()

            if let index = discoveredHosts.firstIndex(where: { $0.id == id }) {
                discoveredHosts[index].services.insert(serviceType)
            } else {
                let host = NetworkHost(
                    id: id,
                    name: name,
                    hostname: hostname,
                    services: [serviceType]
                )
                discoveredHosts.append(host)
            }
        }
    }

    // MARK: - Share Enumeration

    func enumerateShares(on hostname: String, credentials: NetworkCredentials? = nil) async -> ShareEnumerationResult {
        let cleanHost = hostname.replacingOccurrences(of: ".local", with: "")

        // Build the smbutil URL with optional credentials
        let smbURL: String
        if let creds = credentials, !creds.username.isEmpty {
            let escapedUser = creds.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? creds.username
            let escapedPass = creds.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? creds.password
            smbURL = "//\(escapedUser):\(escapedPass)@\(cleanHost)"
        } else {
            smbURL = "//\(cleanHost)"
        }

        let result = await runProcess("/usr/bin/smbutil", arguments: ["view", smbURL])

        // Check for auth errors
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("authentication") || result.exitCode == 68 || result.exitCode == 77 {
                return .authRequired
            }
            return .error(result.stderr.isEmpty ? "Failed to connect to \(cleanHost)" : result.stderr)
        }

        let parsed = parseShareOutput(result.stdout, hostname: hostname)
        shares[hostname] = parsed
        return .success(parsed)
    }

    private func parseShareOutput(_ output: String, hostname: String) -> [NetworkShare] {
        var parsed: [NetworkShare] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("Disk") else { continue }
            // Format: "ShareName          Disk    description"
            let parts = trimmed.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
            guard let shareName = parts.first, !shareName.isEmpty else { continue }
            let share = NetworkShare(
                id: "\(hostname)/\(shareName)",
                name: shareName,
                hostname: hostname,
                type: .smb
            )
            parsed.append(share)
        }
        return parsed
    }

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func runProcess(_ path: String, arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(filePath: path)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let result = ProcessResult(
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: ProcessResult(stdout: "", stderr: error.localizedDescription, exitCode: -1))
                }
            }
        }
    }

    // MARK: - Mounting

    func mountShare(url: URL, credentials: NetworkCredentials? = nil) async -> URL? {
        // Build authenticated smb:// URL
        var mountURLString = url.absoluteString
        if let creds = credentials, !creds.username.isEmpty {
            let escapedUser = creds.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? creds.username
            let escapedPass = creds.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? creds.password
            // Insert user:pass@ after the scheme://
            if let schemeRange = mountURLString.range(of: "://") {
                let insertionPoint = schemeRange.upperBound
                mountURLString.insert(contentsOf: "\(escapedUser):\(escapedPass)@", at: insertionPoint)
            }
        }

        // Use AppleScript "mount volume" which mounts silently with embedded credentials
        let script = "mount volume \"\(mountURLString)\""
        let result = await runProcess("/usr/bin/osascript", arguments: ["-e", script])

        if result.exitCode == 0 {
            // osascript returns the mount path like "file Macintosh HD:Volumes:sharename:"
            // Find the actual mount point in /Volumes
            let shareName = url.lastPathComponent
            let volumePath = URL(filePath: "/Volumes/\(shareName)")
            if FileManager.default.fileExists(atPath: volumePath.path) {
                return volumePath
            }
            // Also check stdout for the path (format varies)
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                // Try to find any newly mounted volume matching the share name
                let fm = FileManager.default
                if let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
                    for vol in volumes where vol.lastPathComponent.lowercased() == shareName.lowercased() {
                        return vol
                    }
                }
            }
        }

        return nil
    }

    // MARK: - FileItem Conversion

    private func sfSymbolImage(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(named: NSImage.networkName)!
    }

    func hostsAsFileItems() -> [FileItem] {
        let icon = sfSymbolImage("desktopcomputer")
        return discoveredHosts.map { host in
            FileItem(
                id: host.networkURL,
                name: host.name,
                isDirectory: true,
                isPackage: false,
                isHidden: false,
                fileSize: 0,
                dateModified: nil,
                kind: "Network Computer",
                icon: icon,
                deferredIconURL: nil
            )
        }
    }

    func sharesAsFileItems(for hostname: String) -> [FileItem] {
        guard let hostShares = shares[hostname] else { return [] }
        let icon = sfSymbolImage("externaldrive.connected.to.line.below")
        return hostShares.map { share in
            FileItem(
                id: share.mountURL,
                name: share.name,
                isDirectory: true,
                isPackage: false,
                isHidden: false,
                fileSize: 0,
                dateModified: nil,
                kind: "Network Share",
                icon: icon,
                deferredIconURL: nil
            )
        }
    }
}
