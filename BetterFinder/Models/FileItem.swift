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

    var url: URL { id }
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
