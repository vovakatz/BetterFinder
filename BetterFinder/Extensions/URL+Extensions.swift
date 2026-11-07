import Foundation

extension URL {
    var displayName: String {
        FileManager.default.displayName(atPath: path(percentEncoded: false))
    }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var isPackage: Bool {
        (try? resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    /// Compares paths, since `==` treats a folder's URL with and without a
    /// trailing slash as different.
    func isSameLocation(as other: URL) -> Bool {
        standardizedFileURL.path == other.standardizedFileURL.path
    }
}
