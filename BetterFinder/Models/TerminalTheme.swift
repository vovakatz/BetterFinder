import SwiftTerm
import AppKit

enum TerminalTheme: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case rainbow12bit = "12-bit Rainbow"
    case aardvarkBlue = "Aardvark Blue"
    case adventure = "Adventure"
    case adventureTime = "Adventure Time"
    case belafonteNight = "Belafonte Night"
    case chester = "Chester"
    case cutiePro = "Cutie Pro"
    case flat = "Flat"

    var id: String { rawValue }

    // MARK: - Apply Theme

    @MainActor
    func apply(to tv: LocalProcessTerminalView) {
        let c = colorData
        tv.installColors(c.ansi.map(Self.makeTermColor))

        if self == .default {
            tv.configureNativeColors()
            tv.caretColor = .textColor
        } else {
            tv.nativeForegroundColor = Self.makeNSColor(c.foreground)
            tv.nativeBackgroundColor = Self.makeNSColor(c.background)
            tv.caretColor = Self.makeNSColor(c.cursor)
        }
    }

    // MARK: - Color Conversion

    private static func makeTermColor(_ hex: UInt32) -> Color {
        Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257
        )
    }

    private static func makeNSColor(_ hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Color Data

    private struct ColorData {
        let ansi: [UInt32] // 16 ANSI colors: black, red, green, yellow, blue, purple, cyan, white, then bright variants
        let foreground: UInt32
        let background: UInt32
        let cursor: UInt32
    }

    private var colorData: ColorData {
        switch self {
        case .default:
            return ColorData(
                ansi: [
                    0x000000, 0xCD0000, 0x00CD00, 0xCDCD00, 0x0000EE, 0xCD00CD, 0x00CDCD, 0xE5E5E5,
                    0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x5C5CFF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
                ],
                foreground: 0x000000,
                background: 0xFFFFFF,
                cursor: 0x000000
            )
        case .rainbow12bit:
            return ColorData(
                ansi: [
                    0x000000, 0xA03050, 0x40D080, 0xE09040, 0x3060B0, 0x603090, 0x0090C0, 0xDBDED8,
                    0x685656, 0xC06060, 0x90D050, 0xE0D000, 0x00B0C0, 0x801070, 0x20B0C0, 0xFFFFFF,
                ],
                foreground: 0xFEFFFF,
                background: 0x040404,
                cursor: 0xE0D000
            )
        case .aardvarkBlue:
            return ColorData(
                ansi: [
                    0x191919, 0xAA342E, 0x4B8C0F, 0xDBBA00, 0x1370D3, 0xC43AC3, 0x008EB0, 0xBEBEBE,
                    0x525252, 0xF05B50, 0x95DC55, 0xFFE763, 0x60A4EC, 0xE26BE2, 0x60B6CB, 0xF7F7F7,
                ],
                foreground: 0xDDDDDD,
                background: 0x102040,
                cursor: 0x007ACC
            )
        case .adventure:
            return ColorData(
                ansi: [
                    0x040404, 0xD84A33, 0x5DA602, 0xEEBB6E, 0x417AB3, 0xE5C499, 0xBDCFE5, 0xDBDED8,
                    0x685656, 0xD76B42, 0x99B52C, 0xFFB670, 0x97D7EF, 0xAA7900, 0xBDCFE5, 0xE4D5C7,
                ],
                foreground: 0xFEFFFF,
                background: 0x040404,
                cursor: 0xFEFFFF
            )
        case .adventureTime:
            return ColorData(
                ansi: [
                    0x050404, 0xBD0013, 0x4AB118, 0xE7741E, 0x0F4AC6, 0x665993, 0x70A598, 0xF8DCC0,
                    0x4E7CBF, 0xFC5F5A, 0x9EFF6E, 0xEFC11A, 0x1997C6, 0x9B5953, 0xC8FAF4, 0xF6F5FB,
                ],
                foreground: 0xF8DCC0,
                background: 0x1F1D45,
                cursor: 0xEFBF38
            )
        case .belafonteNight:
            return ColorData(
                ansi: [
                    0x20111B, 0xBE100E, 0x858162, 0xEAA549, 0x426A79, 0x97522C, 0x989A9C, 0x968C83,
                    0x5E5252, 0xBE100E, 0x858162, 0xEAA549, 0x426A79, 0x97522C, 0x989A9C, 0xD5CCBA,
                ],
                foreground: 0x968C83,
                background: 0x20111B,
                cursor: 0x968C83
            )
        case .chester:
            return ColorData(
                ansi: [
                    0x080200, 0xFA5E5B, 0x16C98D, 0xFFC83F, 0x288AD6, 0xD34590, 0x28DDDE, 0xE7E7E7,
                    0x6F6B68, 0xFA5E5B, 0x16C98D, 0xFEEF6D, 0x278AD6, 0xD34590, 0x27DEDE, 0xFFFFFF,
                ],
                foreground: 0xFFFFFF,
                background: 0x2C3643,
                cursor: 0xB4B1B1
            )
        case .cutiePro:
            return ColorData(
                ansi: [
                    0x000000, 0xF56E7F, 0xBEC975, 0xF58669, 0x42D9C5, 0xD286B7, 0x37CB8A, 0xD5C3C3,
                    0x88847F, 0xE5A1A3, 0xE8D6A7, 0xF1BB79, 0x80C5DE, 0xB294BB, 0x9DCCBB, 0xFFFFFF,
                ],
                foreground: 0xD5D0C9,
                background: 0x181818,
                cursor: 0xEFC4CD
            )
        case .flat:
            return ColorData(
                ansi: [
                    0x222D3F, 0xA82320, 0x32A548, 0xE58D11, 0x3167AC, 0x781AA0, 0x2C9370, 0xB0B6BA,
                    0x475262, 0xD4312E, 0x2D9440, 0xE5BE0C, 0x3C7DD2, 0x8230A7, 0x35B387, 0xE7ECED,
                ],
                foreground: 0x2CC55D,
                background: 0x002240,
                cursor: 0xE5BE0C
            )
        }
    }
}
