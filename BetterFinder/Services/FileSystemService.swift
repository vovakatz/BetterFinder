import Foundation
import UniformTypeIdentifiers

struct FileSystemService {
    nonisolated static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
    ]

    private struct LoadedFileMetadata: Sendable {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isPackage: Bool
        let isHidden: Bool
        let fileSize: Int64
        let dateModified: Date?
        let kind: String
    }

    func loadContents(
        of url: URL,
        showHiddenFiles: Bool,
        sortedBy criteria: SortCriteria
    ) async throws -> [FileItem] {
        let metadata = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try self.loadMetadata(
                        of: url,
                        showHiddenFiles: showHiddenFiles,
                        sortedBy: criteria
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return metadata.map { item in
            FileItem(
                id: item.url,
                name: item.name,
                isDirectory: item.isDirectory,
                isPackage: item.isPackage,
                isHidden: item.isHidden,
                fileSize: item.fileSize,
                dateModified: item.dateModified,
                kind: item.kind,
                icon: FileIconProvider.shared.placeholderIcon(isDirectory: item.isDirectory),
                deferredIconURL: item.url
            )
        }
    }

    private nonisolated func loadMetadata(
        of url: URL,
        showHiddenFiles: Bool,
        sortedBy criteria: SortCriteria
    ) throws -> [LoadedFileMetadata] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: showHiddenFiles ? [] : [.skipsHiddenFiles]
        )

        let items: [LoadedFileMetadata] = contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Self.resourceKeys) else {
                return nil
            }
            let isDir = values.isDirectory ?? false
            let isPackage = values.isPackage ?? false
            return LoadedFileMetadata(
                url: url,
                name: values.name ?? url.lastPathComponent,
                isDirectory: isDir && !isPackage,
                isPackage: isPackage,
                isHidden: values.isHidden ?? false,
                fileSize: Int64(values.fileSize ?? 0),
                dateModified: values.contentModificationDate,
                kind: values.localizedTypeDescription ?? "Unknown"
            )
        }

        return sortItems(items, by: criteria)
    }

    private nonisolated func sortItems(_ items: [LoadedFileMetadata], by criteria: SortCriteria) -> [LoadedFileMetadata] {
        let sorted = items.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }

            let result: Bool
            switch criteria.field {
            case .name:
                result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateModified:
                let dateA = a.dateModified ?? .distantPast
                let dateB = b.dateModified ?? .distantPast
                result = dateA < dateB
            case .size:
                result = a.fileSize < b.fileSize
            case .kind:
                result = a.kind.localizedStandardCompare(b.kind) == .orderedAscending
            }

            return criteria.ascending ? result : !result
        }
        return sorted
    }
}
