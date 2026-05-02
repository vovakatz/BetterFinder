import SwiftUI
import AppKit
import CoreImage

/// macOS tag color index. Mirrors the values stored under the `l` key in
/// the `Tags` array in `com.apple.finder` defaults, and the index Finder
/// shows in its tag editor.
enum TagColor: Int, CaseIterable, Hashable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    /// SwiftUI rendering color tuned to match Finder's actual hues.
    var swiftUIColor: Color {
        switch self {
        case .none:   return Color(white: 0.75)
        case .gray:   return Color(red: 0.66, green: 0.66, blue: 0.69)
        case .green:  return Color(red: 0.46, green: 0.79, blue: 0.36)
        case .purple: return Color(red: 0.74, green: 0.45, blue: 0.83)
        case .blue:   return Color(red: 0.27, green: 0.55, blue: 0.95)
        case .yellow: return Color(red: 0.97, green: 0.82, blue: 0.30)
        case .red:    return Color(red: 0.94, green: 0.34, blue: 0.34)
        case .orange: return Color(red: 0.95, green: 0.59, blue: 0.27)
        }
    }

    /// `true` when this color renders as a hollow ring rather than a filled disk.
    var rendersAsRing: Bool { self == .none }

    /// Bitmap dot suitable for use in `NSMenu` items via `Image(nsImage:)`.
    /// Setting `isTemplate = false` prevents AppKit from re-tinting it with
    /// the menu's text color.
    func dotImage(diameter: CGFloat = 12) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let nsColor = NSColor(swiftUIColor)
        let image = NSImage(size: size, flipped: false) { rect in
            if rendersAsRing {
                NSColor.gray.withAlphaComponent(0.6).setStroke()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()
            } else {
                nsColor.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Returns a recolored copy of `icon` tinted with this tag color.
    /// Uses `CIColorMonochrome` for a Finder-like result that preserves
    /// the icon's depth/shading. Returns the original if tinting fails
    /// or this color renders as a ring (no real color).
    func tinted(_ icon: NSImage) -> NSImage {
        guard !rendersAsRing else { return icon }
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage,
              let ciColor = CIColor(color: NSColor(swiftUIColor)),
              let filter = CIFilter(name: "CIColorMonochrome") else { return icon }

        let baseCI = CIImage(cgImage: cg)
        filter.setValue(baseCI, forKey: kCIInputImageKey)
        filter.setValue(ciColor, forKey: kCIInputColorKey)
        filter.setValue(0.85, forKey: kCIInputIntensityKey)

        guard let output = filter.outputImage,
              let cgOut = TagColor.ciContext.createCGImage(output, from: output.extent) else {
            return icon
        }
        return NSImage(cgImage: cgOut, size: icon.size)
    }

    private static let ciContext = CIContext()
}

struct FileTag: Hashable, Identifiable {
    let name: String
    let color: TagColor

    var id: String { name }
}
