import AppKit
import UniformTypeIdentifiers

final class FileIconProvider {
    static let shared = FileIconProvider()

    private let cache = NSCache<NSURL, NSImage>()
    private lazy var genericFileIcon = NSWorkspace.shared.icon(for: .data)
    private lazy var genericFolderIcon = NSWorkspace.shared.icon(for: .folder)

    private init() {}

    func placeholderIcon(isDirectory: Bool) -> NSImage {
        isDirectory ? genericFolderIcon : genericFileIcon
    }

    func icon(for item: FileItem) -> NSImage {
        guard let url = item.deferredIconURL, url.isFileURL else {
            return item.icon
        }

        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
