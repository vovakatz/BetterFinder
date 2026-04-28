import AppKit
import Foundation

struct TerminalAppOption: Identifiable, Hashable {
    let bundleID: String
    let displayName: String
    let appURL: URL

    var id: String { bundleID }

    static let defaultBundleID = "com.apple.Terminal"

    static let curated: [(bundleID: String, displayName: String)] = [
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("net.kovidgoyal.kitty", "kitty"),
        ("io.alacritty", "Alacritty"),
        ("com.github.wez.wezterm", "WezTerm"),
        ("co.zeit.hyper", "Hyper"),
    ]

    static func installedCurated() -> [TerminalAppOption] {
        curated.compactMap { entry in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else {
                return nil
            }
            return TerminalAppOption(bundleID: entry.bundleID, displayName: entry.displayName, appURL: url)
        }
    }

    static func resolve(bundleID: String) -> TerminalAppOption? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        if let entry = curated.first(where: { $0.bundleID == bundleID }) {
            return TerminalAppOption(bundleID: bundleID, displayName: entry.displayName, appURL: url)
        }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return TerminalAppOption(bundleID: bundleID, displayName: name, appURL: url)
    }
}
