import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import ImageIO

private enum PreviewContent: @unchecked Sendable {
    case none
    case text(String)
    case image(NSImage)
    case pdf(PDFDocument)
    case unsupported(String)
}

struct PreviewWidgetView: View {
    let selectedURLs: Set<URL>
    @Binding var widgetType: WidgetType
    @State private var content: PreviewContent = .none
    @State private var editableText = ""
    @State private var originalText = ""
    @State private var fileModDate: Date?
    @State private var pollTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var viewSize: CGSize = .zero
    @State private var loadedMaxDimension: CGFloat = 0
    @State private var currentImageURL: URL?
    @State private var zoomScale: CGFloat = 1.0
    @State private var steadyZoomScale: CGFloat = 1.0

    private var isTextContent: Bool {
        if case .text = content { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeader
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
                } else {
                    switch content {
                    case .none:
                        Color.clear
                    case .text:
                        TextEditor(text: $editableText)
                            .font(.system(size: 10, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                    case .image(let nsImage):
                        ZoomableImageView(
                            nsImage: nsImage,
                            zoomScale: $zoomScale,
                            steadyZoomScale: $steadyZoomScale
                        )
                    case .pdf(let document):
                        PDFKitView(document: document)
                    case .unsupported(let kind):
                        Text("Preview not available for \(kind)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                let neededMax = max(newSize.width, newSize.height) * 2.0 * zoomScale
                if neededMax > loadedMaxDimension, currentImageURL != nil {
                    viewSize = newSize
                    reloadImageForSize()
                } else {
                    viewSize = newSize
                }
            }
            .onChange(of: zoomScale) { _, newZoom in
                let neededMax = max(viewSize.width, viewSize.height) * 2.0 * newZoom
                if neededMax > loadedMaxDimension, currentImageURL != nil {
                    reloadImageForSize()
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { loadPreviewAsync(); startPolling() }
        .onDisappear { pollTask?.cancel(); loadTask?.cancel() }
        .onChange(of: selectedURLs) { _, _ in loadPreviewAsync(); startPolling() }
        .onChange(of: fileModDate) { _, _ in loadPreviewAsync() }
    }

    private var previewHeader: some View {
        WidgetHeaderView(widgetType: $widgetType) {
            if isTextContent {
                let hasChanges = editableText != originalText
                Button {
                    saveFile()
                } label: {
                    Text("Save")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(hasChanges ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundStyle(hasChanges ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(!hasChanges)
            }
        }
    }

    private func saveFile() {
        guard let url = selectedURLs.first else { return }
        do {
            try editableText.write(to: url, atomically: true, encoding: .utf8)
            originalText = editableText
        } catch {
            // silently fail
        }
    }

    private func loadPreviewAsync() {
        loadTask?.cancel()

        guard selectedURLs.count == 1, let url = selectedURLs.first else {
            content = .none
            editableText = ""
            originalText = ""
            currentImageURL = nil
            loadedMaxDimension = 0
            zoomScale = 1.0
            steadyZoomScale = 1.0
            return
        }

        if url != currentImageURL {
            zoomScale = 1.0
            steadyZoomScale = 1.0
        }

        // Use 800 default when view hasn't laid out yet, covers most widget sizes at 2x
        let maxDimension = viewSize == .zero ? 800.0 : max(viewSize.width, viewSize.height) * 2.0
        loadTask = Task {
            let result = await loadPreviewContent(url: url, maxDimension: maxDimension)
            guard !Task.isCancelled else { return }
            content = result.content
            editableText = result.editableText
            originalText = result.originalText
            currentImageURL = result.isImage ? url : nil
            loadedMaxDimension = result.isImage ? result.loadedDimension : 0
        }
    }

    private func reloadImageForSize() {
        loadTask?.cancel()
        guard let url = currentImageURL else { return }
        let maxDimension = max(viewSize.width, viewSize.height) * 2.0 * zoomScale

        loadTask = Task {
            let result = await Self.loadDownsampledImage(url: url, maxDimension: maxDimension)
            guard !Task.isCancelled else { return }
            content = result.content
            loadedMaxDimension = result.loadedDimension
        }
    }

    private struct PreviewResult: Sendable {
        let content: PreviewContent
        let editableText: String
        let originalText: String
        let isImage: Bool
        let loadedDimension: CGFloat

        nonisolated init(content: PreviewContent, editableText: String = "", originalText: String = "", isImage: Bool = false, loadedDimension: CGFloat = 0) {
            self.content = content
            self.editableText = editableText
            self.originalText = originalText
            self.isImage = isImage
            self.loadedDimension = loadedDimension
        }
    }

    private static func loadDownsampledImage(url: URL, maxDimension: CGFloat) async -> PreviewResult {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return PreviewResult(content: .unsupported("Image"), isImage: true)
            }

            // Get original image dimensions to avoid upsampling
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
            let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
            let originalMax = max(pixelWidth, pixelHeight)

            let requestedSize = max(maxDimension, 100)
            let isFullResolution = originalMax > 0 && requestedSize >= originalMax
            let thumbnailSize = isFullResolution ? originalMax : requestedSize

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return PreviewResult(content: .unsupported("Image"), isImage: true)
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            // If at full resolution, report infinity so we never try to reload larger
            let reportedDimension: CGFloat = isFullResolution ? .greatestFiniteMagnitude : requestedSize
            return PreviewResult(content: .image(nsImage), isImage: true, loadedDimension: reportedDimension)
        }.value
    }

    private func loadPreviewContent(url: URL, maxDimension: CGFloat) async -> PreviewResult {
        await Task.detached(priority: .userInitiated) {
            guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
                  let utType = resourceValues.contentType else {
                return PreviewResult(content: .unsupported("Unknown"))
            }

            if utType.conforms(to: .pdf) {
                if let document = PDFDocument(url: url) {
                    return PreviewResult(content: .pdf(document))
                } else {
                    return PreviewResult(content: .unsupported(utType.localizedDescription ?? utType.identifier))
                }
            } else if utType.conforms(to: .image) {
                return await Self.loadDownsampledImage(url: url, maxDimension: maxDimension)
            } else if utType.conforms(to: .text)
                        || utType.conforms(to: .sourceCode)
                        || utType.conforms(to: .json)
                        || utType.conforms(to: .xml)
                        || utType.conforms(to: .yaml)
                        || utType.conforms(to: .propertyList) {
                return Self.loadTextResult(from: url, utType: utType)
            } else {
                return Self.loadTextResult(from: url, utType: utType)
            }
        }.value
    }

    nonisolated private static func loadTextResult(from url: URL, utType: UTType) -> PreviewResult {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            if fileSize > 100_000 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                return PreviewResult(content: .unsupported("File too large to edit (\(sizeStr))"))
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                return PreviewResult(content: .text(text), editableText: text, originalText: text)
            }
        } catch {
            return PreviewResult(content: .unsupported(utType.localizedDescription ?? utType.identifier))
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        guard selectedURLs.count == 1, let url = selectedURLs.first, url.isFileURL else {
            pollTask = nil
            return
        }
        fileModDate = modificationDate(of: url)
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                let newDate = modificationDate(of: url)
                if newDate != fileModDate {
                    fileModDate = newDate
                }
            }
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

private struct ZoomableImageView: View {
    let nsImage: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var steadyZoomScale: CGFloat

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: geo.size.width * zoomScale,
                        height: geo.size.height * zoomScale
                    )
                    .frame(
                        minWidth: geo.size.width,
                        minHeight: geo.size.height
                    )
            }
            .scrollIndicators(.hidden)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoomScale = max(1.0, steadyZoomScale * value.magnification)
                    }
                    .onEnded { value in
                        zoomScale = max(1.0, steadyZoomScale * value.magnification)
                        steadyZoomScale = zoomScale
                    }
            )
        }
        .padding(8)
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
