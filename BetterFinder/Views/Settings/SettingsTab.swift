import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        }
    }

    /// SF Symbol name used in the settings tab bar.
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        }
    }
}
