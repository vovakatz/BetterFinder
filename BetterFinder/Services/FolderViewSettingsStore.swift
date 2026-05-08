import Foundation

/// Per-folder view-setting deviations from the app-wide defaults.
/// Stores `viewMode`, `sortCriteria`, and `showHiddenFiles` per folder path —
/// but only when the user explicitly differs from `AppSettings`. When all three
/// fields revert to the default the entry is removed.
@MainActor
final class FolderViewSettingsStore {
    static let shared = FolderViewSettingsStore()

    private static let storeKey = "folderViewSettings.v2"
    private static let legacySortKey = "folderSortOrders"
    private static let legacyHiddenKey = "folderShowHiddenFiles"

    private var entries: [String: FolderViewSettings]

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: FolderViewSettings].self, from: data) {
            self.entries = decoded
            return
        }

        var migrated: [String: FolderViewSettings] = [:]

        if let data = defaults.data(forKey: Self.legacySortKey),
           let legacySort = try? JSONDecoder().decode([String: SortCriteria].self, from: data) {
            for (path, criteria) in legacySort {
                var entry = migrated[path] ?? FolderViewSettings()
                entry.sortCriteria = criteria
                migrated[path] = entry
            }
        }

        if let legacyHidden = defaults.stringArray(forKey: Self.legacyHiddenKey) {
            for path in legacyHidden {
                var entry = migrated[path] ?? FolderViewSettings()
                entry.showHiddenFiles = true
                migrated[path] = entry
            }
        }

        self.entries = migrated

        if !migrated.isEmpty {
            persist()
        }
        defaults.removeObject(forKey: Self.legacySortKey)
        defaults.removeObject(forKey: Self.legacyHiddenKey)
    }

    func settings(for path: String) -> FolderViewSettings {
        entries[path] ?? FolderViewSettings()
    }

    func update(for path: String, _ mutate: (inout FolderViewSettings) -> Void) {
        var entry = entries[path] ?? FolderViewSettings()
        mutate(&entry)
        if entry.isEmpty {
            entries.removeValue(forKey: path)
        } else {
            entries[path] = entry
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}
