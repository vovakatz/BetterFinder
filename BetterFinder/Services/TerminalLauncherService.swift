import AppKit
import Foundation

struct TerminalLauncherService {
    private static let keystrokeDelay: TimeInterval = 0.5

    func openTerminal(at folderURL: URL) {
        guard let terminalURL = resolvedTerminalAppURL() else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: terminalURL,
            configuration: config,
            completionHandler: nil
        )
    }

    func openTerminal(at folderURL: URL, prefilledFilename: String) {
        openTerminal(at: folderURL)
        let textToType = Self.shellSingleQuoted(prefilledFilename) + " "
        let appleScriptLiteral = Self.appleScriptStringLiteral(textToType)
        let source = """
        tell application "System Events"
            keystroke \(appleScriptLiteral)
        end tell
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keystrokeDelay) {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
        }
    }

    private func resolvedTerminalAppURL() -> URL? {
        let bundleID = AppSettings.shared.terminalBundleID
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalAppOption.defaultBundleID)
    }

    private static func shellSingleQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptStringLiteral(_ string: String) -> String {
        var escaped = ""
        for char in string {
            switch char {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            default: escaped.append(char)
            }
        }
        return "\"\(escaped)\""
    }
}
