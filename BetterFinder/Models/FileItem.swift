import Foundation
import AppKit

struct FileItem: Identifiable {
    let id: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let fileSize: Int64
    let dateModified: Date?
    let kind: String
    let icon: NSImage
    let deferredIconURL: URL?
    let dateModifiedDisplay: String
    let fileSizeDisplay: String

    var url: URL { id }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(
        id: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool,
        isHidden: Bool,
        fileSize: Int64,
        dateModified: Date?,
        kind: String,
        icon: NSImage,
        deferredIconURL: URL? = nil,
        dateModifiedDisplay: String? = nil,
        fileSizeDisplay: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.fileSize = fileSize
        self.dateModified = dateModified
        self.kind = kind
        self.icon = icon
        self.deferredIconURL = deferredIconURL
        self.dateModifiedDisplay = dateModifiedDisplay ?? {
            guard let dateModified else { return "--" }
            return Self.dateFormatter.string(from: dateModified)
        }()
        self.fileSizeDisplay = fileSizeDisplay ?? (isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
    }
}

extension FileItem: Equatable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
            && lhs.fileSize == rhs.fileSize
            && lhs.dateModified == rhs.dateModified
    }
}

extension FileItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
