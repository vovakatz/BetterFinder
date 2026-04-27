import Foundation
import AppKit

enum DefaultLocation: String, Codable, CaseIterable, Identifiable {
    case home
    case lastLocation
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return "Home Folder"
        case .lastLocation: return "Last Location"
        case .custom: return "Custom…"
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let showHiddenFilesByDefault = "settings.general.showHiddenFilesByDefault"
        static let defaultLocation = "settings.general.defaultLocation"
        static let customDefaultLocationPath = "settings.general.customDefaultLocationPath"
        static let lastLocationPath = "settings.general.lastLocationPath"
        static let defaultSortCriteria = "settings.general.defaultSortCriteria"
    }

    var showHiddenFilesByDefault: Bool {
        didSet { UserDefaults.standard.set(showHiddenFilesByDefault, forKey: Keys.showHiddenFilesByDefault) }
    }

    var defaultLocation: DefaultLocation {
        didSet { UserDefaults.standard.set(defaultLocation.rawValue, forKey: Keys.defaultLocation) }
    }

    var customDefaultLocationPath: String {
        didSet { UserDefaults.standard.set(customDefaultLocationPath, forKey: Keys.customDefaultLocationPath) }
    }

    var lastLocationPath: String {
        didSet { UserDefaults.standard.set(lastLocationPath, forKey: Keys.lastLocationPath) }
    }

    var defaultSortCriteria: SortCriteria {
        didSet {
            if let data = try? JSONEncoder().encode(defaultSortCriteria) {
                UserDefaults.standard.set(data, forKey: Keys.defaultSortCriteria)
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard

        self.showHiddenFilesByDefault = defaults.bool(forKey: Keys.showHiddenFilesByDefault)

        if let raw = defaults.string(forKey: Keys.defaultLocation),
           let loc = DefaultLocation(rawValue: raw) {
            self.defaultLocation = loc
        } else {
            self.defaultLocation = .home
        }

        self.customDefaultLocationPath = defaults.string(forKey: Keys.customDefaultLocationPath) ?? ""
        self.lastLocationPath = defaults.string(forKey: Keys.lastLocationPath) ?? ""

        if let data = defaults.data(forKey: Keys.defaultSortCriteria),
           let decoded = try? JSONDecoder().decode(SortCriteria.self, from: data) {
            self.defaultSortCriteria = decoded
        } else {
            self.defaultSortCriteria = .default
        }
    }

    /// Returns the URL a fresh pane should open to, based on `defaultLocation`.
    /// Falls back to the home directory if the configured path is missing or unreadable.
    func initialURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch defaultLocation {
        case .home:
            return home
        case .lastLocation:
            return resolveDirectory(at: lastLocationPath) ?? home
        case .custom:
            return resolveDirectory(at: customDefaultLocationPath) ?? home
        }
    }

    private func resolveDirectory(at path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
