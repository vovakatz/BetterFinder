import Foundation

enum SidebarCategory: String {
    case favorites
    case volumes
    case network
}

struct SidebarItem: Identifiable, Hashable {
    private static let trashURL = try? FileManager.default.url(
        for: .trashDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    )

    let id: URL
    let name: String
    let icon: String
    let category: SidebarCategory
    var isDefault: Bool = false

    var url: URL { id }

    var isTrash: Bool {
        guard let trashURL = Self.trashURL else { return false }
        return url.standardizedFileURL == trashURL.standardizedFileURL
    }
}
