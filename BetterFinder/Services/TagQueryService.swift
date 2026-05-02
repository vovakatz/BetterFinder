import Foundation
import AppKit
import UniformTypeIdentifiers

/// Wraps `NSMetadataQuery` to enumerate all files tagged with a given
/// `FileTag` across the local computer + user home scope. One instance
/// per active tag-results view; deliver results via `onUpdate`.
final class TagQueryService {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning: Bool = false

    var onUpdate: (([FileItem]) -> Void)?
    var onGatheringFinished: (() -> Void)?

    func start(for tag: FileTag) {
        stop()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemUserTags == %@", tag.name)
        query.searchScopes = [
            NSMetadataQueryLocalComputerScope,
            NSMetadataQueryUserHomeScope,
        ]
        query.notificationBatchingInterval = 0.5

        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.publishResults(from: query)
            self?.onGatheringFinished?()
        })

        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.publishResults(from: query)
        })

        self.query = query
        isRunning = true
        query.start()
    }

    func stop() {
        if let query = query {
            query.stop()
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
        }
        query = nil
        isRunning = false
    }

    private func publishResults(from query: NSMetadataQuery) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var items: [FileItem] = []
        items.reserveCapacity(query.resultCount)
        for i in 0..<query.resultCount {
            guard let result = query.result(at: i) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            if let item = Self.makeFileItem(from: url) {
                items.append(item)
            }
        }
        onUpdate?(items)
    }

    /// Synchronous lightweight `FileItem` from a URL. Resource keys
    /// requested are the same as `FileSystemService.resourceKeys`.
    private static func makeFileItem(from url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: FileSystemService.resourceKeys) else {
            return nil
        }
        let isDir = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        return FileItem(
            id: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: isDir && !isPackage,
            isPackage: isPackage,
            isHidden: values.isHidden ?? false,
            fileSize: Int64(values.fileSize ?? 0),
            dateModified: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? "Unknown",
            icon: FileIconProvider.shared.placeholderIcon(isDirectory: isDir),
            deferredIconURL: url,
            tags: TagService.shared.resolve(names: values.tagNames ?? [])
        )
    }
}
