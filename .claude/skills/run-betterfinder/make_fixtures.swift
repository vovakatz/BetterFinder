// Generates distinctly colored JPEGs so grid cells are easy to tell apart in snapshots.
// Usage: make_fixtures <directory> <count>
// Files past the first 12 are copies, which APFS clones at no disk cost.
import Cocoa

let directory = CommandLine.arguments[1]
let count = Int(CommandLine.arguments[2]) ?? 12
let palette = 12
let manager = FileManager.default
try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)

func fileURL(_ index: Int) -> URL {
    URL(fileURLWithPath: directory).appendingPathComponent(String(format: "IMG_%04d.jpg", index))
}

for index in 0..<min(count, palette) {
    let image = NSImage(size: NSSize(width: 640, height: 480))
    image.lockFocus()
    NSColor(hue: CGFloat(index) / CGFloat(palette), saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 480).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .jpeg, properties: [:])!.write(to: fileURL(index))
}

for index in stride(from: palette, to: count, by: 1) {
    try manager.copyItem(at: fileURL(index % palette), to: fileURL(index))
}
print("\(count) images in \(directory)")
