import Foundation
import CoreServices
import UniformTypeIdentifiers

/// Wraps LaunchServices to read/write whether BetterFinder is the default
/// handler for `public.folder`. The system stores this preference per-user;
/// no UserDefaults mirror.
enum DefaultFolderHandlerService {
    private static let folderContentType = UTType.folder.identifier

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.KatzStudio.BetterFinder"
    }

    static var isDefault: Bool {
        guard let current = LSCopyDefaultRoleHandlerForContentType(
            folderContentType as CFString,
            .viewer
        )?.takeRetainedValue() as String? else {
            return false
        }
        return current.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }

    /// On enable: claim the role for `public.folder`.
    /// On disable: clear it (LaunchServices will then fall back to its system default, typically Finder).
    @discardableResult
    static func setDefault(_ enabled: Bool) -> OSStatus {
        let target = enabled ? bundleIdentifier as CFString : "" as CFString
        return LSSetDefaultRoleHandlerForContentType(
            folderContentType as CFString,
            .viewer,
            target
        )
    }
}
