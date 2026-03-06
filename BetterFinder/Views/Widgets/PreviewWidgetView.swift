import SwiftUI
import UniformTypeIdentifiers
import PDFKit

private enum PreviewContent {
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
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
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
        }
        .frame(maxHeight: .infinity)
        .onAppear { loadPreview(); startPolling() }
        .onDisappear { pollTask?.cancel() }
        .onChange(of: selectedURLs) { _, _ in loadPreview(); startPolling() }
        .onChange(of: fileModDate) { _, _ in loadPreview() }
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

    private func loadPreview() {
        guard selectedURLs.count == 1, let url = selectedURLs.first else {
            content = .none
            editableText = ""
            originalText = ""
            return
        }

        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let utType = resourceValues.contentType else {
            content = .unsupported("Unknown")
            editableText = ""
            originalText = ""
            return
        }

        if utType.conforms(to: .pdf) {
            editableText = ""
            originalText = ""
            if let document = PDFDocument(url: url) {
                content = .pdf(document)
            } else {
                content = .unsupported(utType.localizedDescription ?? utType.identifier)
            }
        } else if utType.conforms(to: .image) {
            editableText = ""
            originalText = ""
            if let nsImage = NSImage(contentsOf: url) {
                content = .image(nsImage)
            } else {
                content = .unsupported(utType.localizedDescription ?? utType.identifier)
            }
        } else if utType.conforms(to: .text)
                    || utType.conforms(to: .sourceCode)
                    || utType.conforms(to: .json)
                    || utType.conforms(to: .xml)
                    || utType.conforms(to: .yaml)
                    || utType.conforms(to: .propertyList) {
            loadTextContent(from: url, utType: utType)
        } else {
            // Unknown UTType — try reading as UTF-8 text as a fallback
            loadTextContent(from: url, utType: utType)
        }
    }

    private func loadTextContent(from url: URL, utType: UTType) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            if fileSize > 100_000 {
                editableText = ""
                originalText = ""
                content = .unsupported("File too large to edit (\(fileSize.formattedFileSize))")
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                editableText = text
                originalText = text
                content = .text(text)
            }
        } catch {
            editableText = ""
            originalText = ""
            content = .unsupported(utType.localizedDescription ?? utType.identifier)
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
