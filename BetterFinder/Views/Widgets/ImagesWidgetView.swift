import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct ImagesWidgetView: View {
    let currentDirectory: URL
    @Binding var selectedURLs: Set<URL>
    @Binding var widgetType: WidgetType

    @State private var imageItems: [FileItem] = []
    @State private var lastClickURL: URL?
    @State private var lastClickTime: Date?

    private static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
        .effectiveIconKey,
        .contentTypeKey,
    ]

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeaderView(widgetType: $widgetType)

            if imageItems.isEmpty {
                ContentUnavailableView("No images in this folder", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(imageItems) { item in
                            ImageCell(item: item, isSelected: selectedURLs.contains(item.url))
                                .onTapGesture {
                                    selectedURLs = [item.url]
                                    let now = Date()
                                    if item.url == lastClickURL,
                                       let last = lastClickTime,
                                       now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
                                        NSWorkspace.shared.open(item.url)
                                        lastClickTime = nil
                                        lastClickURL = nil
                                    } else {
                                        lastClickTime = now
                                        lastClickURL = item.url
                                    }
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .task(id: currentDirectory) {
            loadImages()
        }
    }

    private func loadImages() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            imageItems = []
            return
        }

        imageItems = contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Self.resourceKeys),
                  let contentType = values.contentType,
                  contentType.conforms(to: .image) else {
                return nil
            }
            let isDir = values.isDirectory ?? false
            let isPackage = values.isPackage ?? false
            return FileItem(
                id: url,
                name: values.name ?? url.lastPathComponent,
                isDirectory: isDir && !isPackage,
                isPackage: isPackage,
                isHidden: values.isHidden ?? false,
                fileSize: Int64(values.fileSize ?? 0),
                dateModified: values.contentModificationDate,
                kind: values.localizedTypeDescription ?? "Image",
                icon: values.effectiveIcon as? NSImage ?? NSWorkspace.shared.icon(for: .image),
                deferredIconURL: nil
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct ImageCell: View {
    let item: FileItem
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: item.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(item.name)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 110)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 160, height: 160),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.nsImage
        } catch {
            // Keep the system icon as fallback
        }
    }
}
