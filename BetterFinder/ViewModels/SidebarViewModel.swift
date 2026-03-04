import Foundation

private struct StoredFavorite: Codable {
    let path: String
    let name: String
    let icon: String
    let isDefault: Bool
}

@Observable
final class SidebarViewModel {
    private static let favoritesKey = "SidebarFavorites"

    let volumeService = VolumeService()

    var favorites: [SidebarItem] {
        didSet { saveFavorites() }
    }

    init() {
        let defaults = Self.defaultFavorites()
        if let saved = Self.loadFavorites() {
            favorites = saved
        } else {
            favorites = defaults
        }
    }

    func removeFavorite(_ item: SidebarItem) {
        favorites.removeAll { $0.id == item.id }
    }

    func insertFavorite(url: URL, at index: Int) {
        guard url.isDirectory, !favorites.contains(where: { $0.id == url }) else { return }
        let name = url.displayName
        let item = SidebarItem(id: url, name: name, icon: "folder", category: .favorites)
        let clampedIndex = min(index, favorites.count)
        favorites.insert(item, at: clampedIndex)
    }

    private static func defaultFavorites() -> [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        var items = [
            SidebarItem(id: home, name: "Home", icon: "house", category: .favorites, isDefault: true),
            SidebarItem(id: home.appending(path: "Desktop"), name: "Desktop", icon: "menubar.dock.rectangle", category: .favorites, isDefault: true),
            SidebarItem(id: home.appending(path: "Documents"), name: "Documents", icon: "doc", category: .favorites, isDefault: true),
            SidebarItem(id: home.appending(path: "Downloads"), name: "Downloads", icon: "arrow.down.circle", category: .favorites, isDefault: true),
            SidebarItem(id: URL(filePath: "/Applications"), name: "Applications", icon: "app.dashed", category: .favorites, isDefault: true),
        ]
        if let trashURL {
            items.append(SidebarItem(id: trashURL, name: "Trash", icon: "trash", category: .favorites, isDefault: true))
        }
        return items
    }

    private func saveFavorites() {
        let stored = favorites.map { StoredFavorite(path: $0.url.path(percentEncoded: false), name: $0.name, icon: $0.icon, isDefault: $0.isDefault) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    private static func loadFavorites() -> [SidebarItem]? {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let stored = try? JSONDecoder().decode([StoredFavorite].self, from: data) else { return nil }
        return stored.map {
            SidebarItem(id: URL(filePath: $0.path), name: $0.name, icon: $0.icon, category: .favorites, isDefault: $0.isDefault)
        }
    }

    var networkItem: SidebarItem {
        SidebarItem(
            id: URL(string: "network://")!,
            name: "Network",
            icon: "network",
            category: .network
        )
    }

    var localVolumes: [SidebarItem] {
        volumeService.localVolumes
    }

    var networkVolumes: [SidebarItem] {
        volumeService.networkVolumes
    }

    var volumes: [SidebarItem] {
        volumeService.volumes
    }
}
