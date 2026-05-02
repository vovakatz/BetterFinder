import Foundation
import AppKit

/// Source of truth for the tag catalog and per-file tag I/O.
///
/// The catalog (available tags, their colors, and the sidebar favorites
/// list) is read from Finder's preferences (`com.apple.finder` defaults).
/// BetterFinder is a read-only consumer of that catalog — users continue
/// to manage tags in Finder Settings → Tags.
@Observable
final class TagService {
    static let shared = TagService()

    /// Full catalog: every tag name → its color.
    private(set) var catalog: [String: TagColor] = [:]

    /// All known tags sorted by name. Used by the picker for autocomplete.
    private(set) var availableTags: [FileTag] = []

    /// Sidebar favorites in order. `nil` entries represent separators
    /// (Finder stores empty strings as separators in `FavoriteTagNames`).
    private(set) var favoriteTags: [FileTag?] = []

    @MainActor
    private init() {
        loadCatalog()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @MainActor
    @objc private func appDidBecomeActive() {
        loadCatalog()
    }

    /// Resolves a list of raw tag names into `FileTag` values using the catalog.
    /// Names not in the catalog are returned with color `.none`.
    func resolve(names: [String]) -> [FileTag] {
        names.map { FileTag(name: $0, color: catalog[$0] ?? .none) }
    }

    @MainActor
    private func loadCatalog() {
        let defaults = UserDefaults(suiteName: "com.apple.finder")

        // Tags: array of dicts with at least keys "n" (name, String) and
        // "l" (color index, Int 0–7). Other keys (e.g. "p" for some
        // metadata) are ignored.
        var newCatalog: [String: TagColor] = [:]
        if let rawTags = defaults?.array(forKey: "Tags") as? [[String: Any]] {
            for entry in rawTags {
                guard let name = entry["n"] as? String, !name.isEmpty else { continue }
                let colorIndex = (entry["l"] as? Int) ?? 0
                let color = TagColor(rawValue: colorIndex) ?? .none
                newCatalog[name] = color
            }
        }

        // Fall back to the seven Finder default tags if the catalog is empty
        // (parse failure or fresh user with no customization).
        if newCatalog.isEmpty {
            newCatalog = Self.defaultCatalog
        }

        // FavoriteTagNames: ordered array of strings. Empty strings act as
        // separators in Finder's sidebar; we treat them the same.
        var newFavorites: [FileTag?] = []
        if let rawFavorites = defaults?.array(forKey: "FavoriteTagNames") as? [String] {
            for name in rawFavorites {
                if name.isEmpty {
                    newFavorites.append(nil)
                } else {
                    let color = newCatalog[name] ?? .none
                    newFavorites.append(FileTag(name: name, color: color))
                }
            }
        }

        // If no favorites configured, default to all named catalog tags.
        if newFavorites.isEmpty {
            newFavorites = Self.defaultCatalog.keys.sorted().map { name in
                FileTag(name: name, color: Self.defaultCatalog[name] ?? .none)
            }
        }

        let newAvailable = newCatalog
            .map { FileTag(name: $0.key, color: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        catalog = newCatalog
        availableTags = newAvailable
        favoriteTags = newFavorites
    }

    // MARK: - Per-URL tag I/O

    /// Reads tags for a single URL. Returns `[]` for non-local volumes,
    /// missing files, or any error (callers cannot meaningfully recover
    /// from a per-URL read failure).
    func tags(for url: URL) -> [FileTag] {
        guard url.isFileURL else { return [] }
        let values = try? url.resourceValues(forKeys: [.tagNamesKey])
        let names = values?.tagNames ?? []
        return resolve(names: names)
    }

    /// Writes a tag set to a list of URLs.
    ///
    /// Each URL is attempted independently. On any failure, throws
    /// `TagWriteError` containing the per-URL outcomes so callers can
    /// update in-memory state for the URLs that did succeed.
    @MainActor
    func setTags(_ tags: [FileTag], on urls: [URL]) throws {
        var failures: [(URL, Error)] = []
        var successes: [URL] = []

        let names = tags.map(\.name)

        for url in urls {
            // Non-local volumes silently fail to write tags. Detect and
            // surface as a recognizable error.
            let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? false
            guard url.isFileURL && isLocal else {
                failures.append((url, TagIOError.unsupportedVolume))
                continue
            }

            do {
                var mutableURL = url
                var resourceValues = URLResourceValues()
                resourceValues.tagNames = names
                try mutableURL.setResourceValues(resourceValues)
                successes.append(mutableURL)

                // If the user introduced a tag name that wasn't in the
                // catalog yet, add it with color .none so the picker and
                // dot view can render it immediately.
                for tag in tags where catalog[tag.name] == nil {
                    catalog[tag.name] = tag.color
                }
                if !tags.isEmpty {
                    availableTags = catalog
                        .map { FileTag(name: $0.key, color: $0.value) }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            } catch {
                failures.append((url, error))
            }
        }

        if !failures.isEmpty {
            throw TagWriteError(successes: successes, failures: failures)
        }
    }

    /// Toggle behaviour: if every URL has the tag, removes it from all;
    /// otherwise adds it to every URL that doesn't have it.
    @MainActor
    func toggle(_ tag: FileTag, on urls: [URL]) throws {
        let allHave = urls.allSatisfy { tags(for: $0).contains(tag) }
        for url in urls {
            var current = tags(for: url)
            if allHave {
                current.removeAll { $0 == tag }
            } else if !current.contains(tag) {
                current.append(tag)
            }
            try setTags(current, on: [url])
        }
    }

    /// Hardcoded fallback matching Finder's seven default color tags.
    private static let defaultCatalog: [String: TagColor] = [
        "Red":    .red,
        "Orange": .orange,
        "Yellow": .yellow,
        "Green":  .green,
        "Blue":   .blue,
        "Purple": .purple,
        "Gray":   .gray,
    ]
}

enum TagIOError: Error {
    case unsupportedVolume
}

struct TagWriteError: Error {
    let successes: [URL]
    let failures: [(URL, Error)]

    var localizedDescription: String {
        if failures.contains(where: {
            if case TagIOError.unsupportedVolume = $0.1 { return true }
            return false
        }) {
            return "Tags can't be applied to files on this volume."
        }
        return "Couldn't apply tags to \(failures.count) item\(failures.count == 1 ? "" : "s")."
    }
}
