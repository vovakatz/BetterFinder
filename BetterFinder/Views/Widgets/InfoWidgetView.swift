import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct FileMetadata {
    var name: String = ""
    var kind: String = ""
    var uti: String = ""
    var sizeLogical: Int64 = 0
    var sizePhysical: Int64 = 0
    var created: Date?
    var modified: Date?
    var lastOpened: Date?
    var added: Date?
    var attributes: String = ""
    var owner: String = ""
    var group: String = ""
    var permissions: String = ""
    var path: String = ""
    var application: String = ""
    var volumeName: String = ""
    var volumeCapacity: Int64 = 0
    var volumeFree: Int64 = 0
    var volumeFormat: String = ""
    var mountPoint: String = ""
    var device: String = ""

    static func fetch(from url: URL) -> FileMetadata? {
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey, .localizedTypeDescriptionKey, .contentTypeKey,
            .fileSizeKey, .fileAllocatedSizeKey,
            .creationDateKey, .contentModificationDateKey,
            .contentAccessDateKey, .addedToDirectoryDateKey,
            .isHiddenKey, .isReadableKey, .isWritableKey, .isExecutableKey,
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedFormatDescriptionKey,
        ]

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }

        var meta = FileMetadata()
        meta.name = values.name ?? url.lastPathComponent
        meta.kind = values.localizedTypeDescription ?? "Unknown"
        meta.uti = values.contentType?.identifier ?? ""
        meta.sizeLogical = Int64(values.fileSize ?? 0)
        meta.sizePhysical = Int64(values.fileAllocatedSize ?? 0)
        meta.created = values.creationDate
        meta.modified = values.contentModificationDate
        meta.lastOpened = values.contentAccessDate
        meta.added = values.addedToDirectoryDate
        meta.path = url.path

        // Attributes
        var attrs: [String] = []
        if values.isHidden == true { attrs.append("Hidden") }
        if values.isReadable == true { attrs.append("Readable") }
        if values.isWritable == true { attrs.append("Writable") }
        if values.isExecutable == true { attrs.append("Executable") }
        meta.attributes = attrs.joined(separator: ", ")

        // Owner, group, permissions from FileManager
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            meta.owner = fileAttrs[.ownerAccountName] as? String ?? ""
            meta.group = fileAttrs[.groupOwnerAccountName] as? String ?? ""
            if let posix = fileAttrs[.posixPermissions] as? Int {
                meta.permissions = formatPermissions(posix)
            }
        }

        // Default application
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) {
            meta.application = appURL.deletingPathExtension().lastPathComponent
        }

        // Volume info
        meta.volumeName = values.volumeName ?? ""
        meta.volumeCapacity = values.volumeTotalCapacity.map { Int64($0) } ?? 0
        meta.volumeFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        meta.volumeFormat = values.volumeLocalizedFormatDescription ?? ""
        if let (mount, dev) = mountAndDevice(for: url.path) {
            meta.mountPoint = mount
            meta.device = dev
        }

        return meta
    }
}

private func formatPermissions(_ mode: Int) -> String {
    let chars: [(Int, Character)] = [
        (0o400, "r"), (0o200, "w"), (0o100, "x"),
        (0o040, "r"), (0o020, "w"), (0o010, "x"),
        (0o004, "r"), (0o002, "w"), (0o001, "x"),
    ]
    var str = ""
    for (mask, ch) in chars {
        str.append(mode & mask != 0 ? ch : "-")
    }
    let octal = String(format: "%o", mode & 0o777)
    return "\(str) (\(octal))"
}

private func mountAndDevice(for path: String) -> (mount: String, device: String)? {
    var buf = statfs()
    guard statfs(path, &buf) == 0 else { return nil }
    let device = withUnsafePointer(to: &buf.f_mntfromname) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
            String(cString: $0)
        }
    }
    let mount = withUnsafePointer(to: &buf.f_mntonname) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
            String(cString: $0)
        }
    }
    return (mount, device)
}

struct ImageMetadata {
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var colorModel: String = ""
    var colorProfile: String = ""
    var depth: Int = 0
    var dpiWidth: Double?
    var dpiHeight: Double?
    var hasAlpha: Bool = false

    // EXIF
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var exposureTime: String?
    var fNumber: String?
    var iso: String?
    var focalLength: String?
    var focalLength35mm: String?
    var flash: String?
    var dateTaken: String?
    var whiteBalance: String?
    var meteringMode: String?
    var exposureProgram: String?
    var exposureBias: String?

    // GPS
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?

    var dimensionSummary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let w = formatter.string(from: NSNumber(value: pixelWidth)) ?? "\(pixelWidth)"
        let h = formatter.string(from: NSNumber(value: pixelHeight)) ?? "\(pixelHeight)"
        return "\(w) x \(h)"
    }

    static func fetch(from url: URL) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }

        var meta = ImageMetadata()
        meta.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        meta.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        meta.colorModel = props[kCGImagePropertyColorModel] as? String ?? ""
        meta.colorProfile = props[kCGImagePropertyProfileName] as? String ?? ""
        meta.depth = props[kCGImagePropertyDepth] as? Int ?? 0
        meta.dpiWidth = props[kCGImagePropertyDPIWidth] as? Double
        meta.dpiHeight = props[kCGImagePropertyDPIHeight] as? Double
        meta.hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false

        // EXIF data
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.dateTaken = exif[kCGImagePropertyExifDateTimeOriginal] as? String

            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double {
                if exposure >= 1 {
                    meta.exposureTime = String(format: "%.1fs", exposure)
                } else {
                    let denom = Int(round(1.0 / exposure))
                    meta.exposureTime = "1/\(denom)s"
                }
            }

            if let f = exif[kCGImagePropertyExifFNumber] as? Double {
                meta.fNumber = String(format: "f/%.1f", f)
            }

            if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = isoValues.first {
                meta.iso = "ISO \(first)"
            }

            if let fl = exif[kCGImagePropertyExifFocalLength] as? Double {
                meta.focalLength = String(format: "%.1f mm", fl)
            }

            if let fl35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
                meta.focalLength35mm = "\(fl35) mm"
            }

            if let flashVal = exif[kCGImagePropertyExifFlash] as? Int {
                meta.flash = (flashVal & 0x1) != 0 ? "Fired" : "Did not fire"
            }

            if let wb = exif[kCGImagePropertyExifWhiteBalance] as? Int {
                meta.whiteBalance = wb == 0 ? "Auto" : "Manual"
            }

            if let metering = exif[kCGImagePropertyExifMeteringMode] as? Int {
                switch metering {
                case 1: meta.meteringMode = "Average"
                case 2: meta.meteringMode = "Center-weighted"
                case 3: meta.meteringMode = "Spot"
                case 4: meta.meteringMode = "Multi-spot"
                case 5: meta.meteringMode = "Pattern"
                case 6: meta.meteringMode = "Partial"
                default: meta.meteringMode = "Unknown"
                }
            }

            if let prog = exif[kCGImagePropertyExifExposureProgram] as? Int {
                switch prog {
                case 1: meta.exposureProgram = "Manual"
                case 2: meta.exposureProgram = "Normal"
                case 3: meta.exposureProgram = "Aperture Priority"
                case 4: meta.exposureProgram = "Shutter Priority"
                case 5: meta.exposureProgram = "Creative"
                case 6: meta.exposureProgram = "Action"
                case 7: meta.exposureProgram = "Portrait"
                case 8: meta.exposureProgram = "Landscape"
                default: meta.exposureProgram = nil
                }
            }

            if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double {
                meta.exposureBias = String(format: "%+.1f EV", bias)
            }
        }

        // TIFF data for camera make/model
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }

        // EXIF Aux for lens
        if let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] {
            meta.lensModel = exifAux[kCGImagePropertyExifAuxLensModel] as? String
        }
        // Also check EXIF dict for lens
        if meta.lensModel == nil,
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.lensModel = exif[kCGImagePropertyExifLensModel] as? String
        }

        // GPS data
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String {
                meta.latitude = latRef == "S" ? -lat : lat
            }
            if let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                meta.longitude = lonRef == "W" ? -lon : lon
            }
            meta.altitude = gps[kCGImagePropertyGPSAltitude] as? Double
        }

        // Only return if we got valid dimensions
        guard meta.pixelWidth > 0 && meta.pixelHeight > 0 else { return nil }
        return meta
    }
}

struct InfoWidgetView: View {
    let selectedURLs: Set<URL>
    @Binding var widgetType: WidgetType
    @State private var metadata: FileMetadata?
    @State private var imageMetadata: ImageMetadata?
    @State private var calculatedFolderSize: Int64?
    @State private var isCalculatingSize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeaderView(widgetType: $widgetType)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if selectedURLs.count == 0 {
                    Text("No Selection")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if selectedURLs.count > 1 {
                    Text("\(selectedURLs.count) items selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if let meta = metadata {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            infoRow("Name", meta.name)
                            infoRow("Kind", meta.kind)
                            if !meta.uti.isEmpty {
                                infoRow("UTI", meta.uti)
                            }
                            if let url = selectedURLs.first, url.isDirectory {
                                folderSizeRow
                            } else {
                                infoRow("Size", meta.sizeLogical.formattedFileSize)
                                HStack(alignment: .top, spacing: 4) {
                                    Text("")
                                        .frame(width: 70, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Data: \(meta.sizeLogical) bytes")
                                        Text("Physical: \(meta.sizePhysical) bytes")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                }
                            }
                            if let img = imageMetadata {
                                Divider().padding(.vertical, 4)
                                infoRow("Image", img.dimensionSummary)
                                infoRow("Width", "\(img.pixelWidth) px")
                                infoRow("Height", "\(img.pixelHeight) px")
                                if !img.colorModel.isEmpty {
                                    infoRow("Color", img.colorModel)
                                }
                                if !img.colorProfile.isEmpty {
                                    infoRow("Profile", img.colorProfile)
                                }
                                if img.depth > 0 {
                                    infoRow("Depth", "\(img.depth) bit")
                                }
                                if img.hasAlpha {
                                    infoRow("Alpha", "Yes")
                                }
                                if let dpiW = img.dpiWidth, let dpiH = img.dpiHeight {
                                    if dpiW == dpiH {
                                        infoRow("DPI", String(format: "%.0f", dpiW))
                                    } else {
                                        infoRow("DPI", String(format: "%.0f x %.0f", dpiW, dpiH))
                                    }
                                }

                                // Camera / EXIF section
                                if img.cameraMake != nil || img.cameraModel != nil || img.exposureTime != nil {
                                    Divider().padding(.vertical, 4)
                                    if let make = img.cameraMake {
                                        infoRow("Make", make)
                                    }
                                    if let model = img.cameraModel {
                                        infoRow("Camera", model)
                                    }
                                    if let lens = img.lensModel {
                                        infoRow("Lens", lens)
                                    }
                                    if let exp = img.exposureTime {
                                        infoRow("Exposure", exp)
                                    }
                                    if let f = img.fNumber {
                                        infoRow("Aperture", f)
                                    }
                                    if let iso = img.iso {
                                        infoRow("ISO", iso)
                                    }
                                    if let fl = img.focalLength {
                                        if let fl35 = img.focalLength35mm {
                                            infoRow("Focal Len", "\(fl) (\(fl35) eq.)")
                                        } else {
                                            infoRow("Focal Len", fl)
                                        }
                                    }
                                    if let flash = img.flash {
                                        infoRow("Flash", flash)
                                    }
                                    if let prog = img.exposureProgram {
                                        infoRow("Program", prog)
                                    }
                                    if let metering = img.meteringMode {
                                        infoRow("Metering", metering)
                                    }
                                    if let wb = img.whiteBalance {
                                        infoRow("White Bal", wb)
                                    }
                                    if let bias = img.exposureBias {
                                        infoRow("Exp Bias", bias)
                                    }
                                    if let date = img.dateTaken {
                                        infoRow("Taken", date)
                                    }
                                }

                                // GPS section
                                if let lat = img.latitude, let lon = img.longitude {
                                    Divider().padding(.vertical, 4)
                                    infoRow("Latitude", String(format: "%.6f", lat))
                                    infoRow("Longitude", String(format: "%.6f", lon))
                                    if let alt = img.altitude {
                                        infoRow("Altitude", String(format: "%.1f m", alt))
                                    }
                                }
                            }
                            Divider().padding(.vertical, 4)
                            if let d = meta.created {
                                infoRow("Created", d.fileDateString)
                            }
                            if let d = meta.modified {
                                infoRow("Modified", d.fileDateString)
                            }
                            if let d = meta.lastOpened {
                                infoRow("Opened", d.fileDateString)
                            }
                            if let d = meta.added {
                                infoRow("Added", d.fileDateString)
                            }
                            Divider().padding(.vertical, 4)
                            if !meta.attributes.isEmpty {
                                infoRow("Attrs", meta.attributes)
                            }
                            if !meta.owner.isEmpty {
                                infoRow("Owner", meta.owner)
                            }
                            if !meta.group.isEmpty {
                                infoRow("Group", meta.group)
                            }
                            if !meta.permissions.isEmpty {
                                infoRow("Perms", meta.permissions)
                            }
                            if !meta.application.isEmpty {
                                infoRow("Opens with", meta.application)
                            }
                            infoRow("Path", meta.path)
                            Divider().padding(.vertical, 4)
                            if !meta.volumeName.isEmpty {
                                infoRow("Volume", meta.volumeName)
                            }
                            if meta.volumeCapacity > 0 {
                                infoRow("Capacity", meta.volumeCapacity.formattedFileSize)
                            }
                            if meta.volumeFree > 0 {
                                infoRow("Free", meta.volumeFree.formattedFileSize)
                            }
                            if !meta.volumeFormat.isEmpty {
                                infoRow("Format", meta.volumeFormat)
                            }
                            if !meta.mountPoint.isEmpty {
                                infoRow("Mount", meta.mountPoint)
                            }
                            if !meta.device.isEmpty {
                                infoRow("Device", meta.device)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .onAppear { fetchMetadata() }
        .onChange(of: selectedURLs) { _, _ in fetchMetadata() }
    }

    @ViewBuilder
    private var folderSizeRow: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("Size")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(.secondary)
            if isCalculatingSize {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else if let size = calculatedFolderSize {
                Text(size.formattedFileSize)
                    .textSelection(.enabled)
            } else {
                Button("Calculate") {
                    guard let url = selectedURLs.first else { return }
                    calculateFolderSize(url)
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }
        .font(.system(size: 11))
    }

    private func calculateFolderSize(_ url: URL) {
        isCalculatingSize = true
        Task.detached {
            let size = Self.totalSize(of: url)
            await MainActor.run {
                calculatedFolderSize = size
                isCalculatingSize = false
            }
        }
    }

    private static func totalSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func fetchMetadata() {
        calculatedFolderSize = nil
        isCalculatingSize = false
        if selectedURLs.count == 1, let url = selectedURLs.first {
            metadata = FileMetadata.fetch(from: url)
            // Check if it's an image and fetch image-specific metadata
            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               contentType.conforms(to: .image) {
                imageMetadata = ImageMetadata.fetch(from: url)
            } else {
                imageMetadata = nil
            }
        } else {
            metadata = nil
            imageMetadata = nil
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}
