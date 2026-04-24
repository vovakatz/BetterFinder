import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PDFKit
import ImageIO
import WebKit

private enum PreviewContent: @unchecked Sendable {
    case none
    case text(String)
    case image(NSImage)
    case svg(URL)
    case pdf(PDFDocument)
    case unsupported(String)
}

struct PreviewWidgetView: View {
    let selectedURLs: Set<URL>
    @Binding var widgetType: WidgetType
    @State private var content: PreviewContent = .none
    @State private var editableText = ""
    @State private var originalText = ""
    @State private var textLanguage: SyntaxLanguage?
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
                        SyntaxHighlightingTextView(text: $editableText, language: textLanguage)
                    case .image(let nsImage):
                        ZoomableImageView(
                            nsImage: nsImage,
                            zoomScale: $zoomScale,
                            steadyZoomScale: $steadyZoomScale
                        )
                    case .svg(let url):
                        SVGPreviewView(url: url, reloadToken: fileModDate)
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
            textLanguage = nil
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
            textLanguage = result.textLanguage
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
        let textLanguage: SyntaxLanguage?
        let isImage: Bool
        let loadedDimension: CGFloat

        nonisolated init(content: PreviewContent, editableText: String = "", originalText: String = "", textLanguage: SyntaxLanguage? = nil, isImage: Bool = false, loadedDimension: CGFloat = 0) {
            self.content = content
            self.editableText = editableText
            self.originalText = originalText
            self.textLanguage = textLanguage
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

            if Self.isSVG(url: url, utType: utType) {
                return PreviewResult(content: .svg(url))
            } else if utType.conforms(to: .pdf) {
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

    nonisolated private static func isSVG(url: URL, utType: UTType) -> Bool {
        if utType.identifier == "public.svg-image" {
            return true
        }

        if utType.preferredFilenameExtension?.caseInsensitiveCompare("svg") == .orderedSame {
            return true
        }

        return url.pathExtension.caseInsensitiveCompare("svg") == .orderedSame
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
                return PreviewResult(
                    content: .text(text),
                    editableText: text,
                    originalText: text,
                    textLanguage: SyntaxLanguage.detect(url: url, utType: utType)
                )
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

private enum SyntaxLanguage: Sendable {
    case python
    case sql
    case json
    case swift
    case javascript
    case typescript
    case xml
    case yaml
    case markdown
    case shell

    nonisolated static func detect(url: URL, utType: UTType) -> SyntaxLanguage? {
        switch url.pathExtension.lowercased() {
        case "py", "pyw":
            return .python
        case "sql":
            return .sql
        case "json", "geojson", "jsonl":
            return .json
        case "swift":
            return .swift
        case "js", "jsx", "mjs", "cjs":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "xml", "html", "htm", "plist", "xhtml":
            return .xml
        case "yaml", "yml":
            return .yaml
        case "md", "markdown":
            return .markdown
        case "sh", "bash", "zsh", "command":
            return .shell
        default:
            break
        }

        if utType.conforms(to: .json) {
            return .json
        }
        if utType.conforms(to: .xml) || utType.conforms(to: .propertyList) {
            return .xml
        }
        if utType.conforms(to: .yaml) {
            return .yaml
        }

        return nil
    }
}

private struct SyntaxHighlightingTextView: NSViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = SyntaxHighlighter.font
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        SyntaxHighlighter.apply(to: textView, language: language)
        context.coordinator.language = language

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }
        let languageChanged = context.coordinator.language != language

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            SyntaxHighlighter.apply(to: textView, language: language)
            context.coordinator.isProgrammaticChange = false
        } else if languageChanged {
            SyntaxHighlighter.apply(to: textView, language: language)
        }

        context.coordinator.language = language
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var language: SyntaxLanguage?
        var isProgrammaticChange = false

        init(parent: SyntaxHighlightingTextView) {
            self.parent = parent
            self.language = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            SyntaxHighlighter.apply(to: textView, language: parent.language)
            language = parent.language
        }
    }
}

private enum SyntaxHighlighter {
    struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }

    struct Definition {
        let protectedRules: [Rule]
        let regularRules: [Rule]
    }

    static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    private static let baseColor = NSColor.labelColor
    private static let keywordColor = NSColor.systemBlue
    private static let stringColor = NSColor.systemRed
    private static let commentColor = NSColor.systemGreen
    private static let numberColor = NSColor.systemOrange
    private static let accentColor = NSColor.systemPurple
    private static let propertyColor = NSColor.systemTeal
    private static let symbolColor = NSColor.secondaryLabelColor

    static func apply(to textView: NSTextView, language: SyntaxLanguage?) {
        guard let textStorage = textView.textStorage else { return }

        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let selectedRanges = textView.selectedRanges

        textStorage.beginEditing()
        textStorage.setAttributes(
            [
                .font: font,
                .foregroundColor: baseColor,
            ],
            range: fullRange
        )

        if let language {
            let definition = definition(for: language)
            var protectedRanges: [NSRange] = []

            for rule in definition.protectedRules {
                for range in matches(for: rule, in: text) where !overlapsProtected(range, protectedRanges: protectedRanges) {
                    textStorage.addAttribute(.foregroundColor, value: rule.color, range: range)
                    protectedRanges.append(range)
                }
            }

            for rule in definition.regularRules {
                for range in matches(for: rule, in: text) where !overlapsProtected(range, protectedRanges: protectedRanges) {
                    textStorage.addAttribute(.foregroundColor, value: rule.color, range: range)
                }
            }
        }

        textStorage.endEditing()
        textView.selectedRanges = selectedRanges
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: baseColor,
        ]
    }

    private static func definition(for language: SyntaxLanguage) -> Definition {
        switch language {
        case .python:
            return Definition(
                protectedRules: [
                    rule(#"(?s)(?:[rubf]|br|rb|fr|rf)?\"\"\".*?\"\"\"|(?:[rubf]|br|rb|fr|rf)?'''.*?'''"#, color: stringColor, options: [.caseInsensitive]),
                    rule(#"(?:[rubf]|br|rb|fr|rf)?\"(?:\\.|[^\"\\])*\"|(?:[rubf]|br|rb|fr|rf)?'(?:\\.|[^'\\])*'"#, color: stringColor, options: [.caseInsensitive]),
                    rule(#"#.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"], color: keywordColor),
                    keywordRule(["False", "None", "True"], color: accentColor),
                    rule(#"(?m)@[A-Za-z_][A-Za-z0-9_]*"#, color: accentColor),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        case .sql:
            return Definition(
                protectedRules: [
                    rule(#"'(?:''|[^'])*'"#, color: stringColor),
                    rule(#"/\*[\s\S]*?\*/"#, color: commentColor),
                    rule(#"--.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["select", "from", "where", "join", "left", "right", "inner", "outer", "full", "on", "as", "group", "by", "order", "having", "limit", "offset", "insert", "into", "values", "update", "set", "delete", "create", "alter", "drop", "table", "view", "index", "distinct", "union", "all", "and", "or", "not", "null", "is", "in", "exists", "case", "when", "then", "else", "end"], color: keywordColor, options: [.caseInsensitive]),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        case .json:
            return Definition(
                protectedRules: [
                    rule(#""(?:\\.|[^"\\])*"(?=\s*:)"#, color: propertyColor),
                    rule(#""(?:\\.|[^"\\])*""#, color: stringColor),
                ],
                regularRules: [
                    keywordRule(["true", "false", "null"], color: accentColor),
                    rule(#"-?\b(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: numberColor),
                    rule(#"[{}\[\]:,]"#, color: symbolColor),
                ]
            )
        case .swift:
            return Definition(
                protectedRules: [
                    rule(#"(?s)\"\"\".*?\"\"\""#, color: stringColor),
                    rule(#""(?:\\.|[^"\\])*""#, color: stringColor),
                    rule(#"/\*[\s\S]*?\*/"#, color: commentColor),
                    rule(#"//.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "false", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "private", "protocol", "public", "repeat", "return", "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var", "where", "while"], color: keywordColor),
                    rule(#"@[A-Za-z_][A-Za-z0-9_]*"#, color: accentColor),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        case .javascript:
            return Definition(
                protectedRules: [
                    rule(#"(?s)`(?:\\.|[^`\\])*`"#, color: stringColor),
                    rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: stringColor),
                    rule(#"/\*[\s\S]*?\*/"#, color: commentColor),
                    rule(#"//.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["break", "case", "catch", "class", "const", "continue", "default", "delete", "else", "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "while", "yield"], color: keywordColor),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        case .typescript:
            return Definition(
                protectedRules: [
                    rule(#"(?s)`(?:\\.|[^`\\])*`"#, color: stringColor),
                    rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: stringColor),
                    rule(#"/\*[\s\S]*?\*/"#, color: commentColor),
                    rule(#"//.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["any", "as", "async", "await", "boolean", "break", "case", "catch", "class", "const", "continue", "declare", "default", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "infer", "interface", "keyof", "let", "module", "namespace", "never", "new", "null", "number", "private", "protected", "public", "readonly", "return", "static", "string", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while"], color: keywordColor),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        case .xml:
            return Definition(
                protectedRules: [
                    rule(#"<!--[\s\S]*?-->"#, color: commentColor),
                    rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: stringColor),
                ],
                regularRules: [
                    rule(#"</?[A-Za-z_][A-Za-z0-9:._-]*"#, color: keywordColor),
                    rule(#"\b[A-Za-z_][A-Za-z0-9:._-]*(?=\=)"#, color: propertyColor),
                    rule(#"[<>/=]"#, color: symbolColor),
                ]
            )
        case .yaml:
            return Definition(
                protectedRules: [
                    rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: stringColor),
                    rule(#"#.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    rule(#"(?m)^[ \t-]*[A-Za-z0-9_.\"'/-]+(?=\s*:)"#, color: propertyColor),
                    keywordRule(["true", "false", "null", "~", "yes", "no", "on", "off"], color: accentColor, options: [.caseInsensitive]),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                    rule(#"(?m)^[ \t-]*-"#, color: symbolColor),
                ]
            )
        case .markdown:
            return Definition(
                protectedRules: [
                    rule(#"(?s)```.*?```"#, color: stringColor),
                    rule(#"`[^`\n]+`"#, color: stringColor),
                ],
                regularRules: [
                    rule(#"(?m)^#{1,6}\s.+$"#, color: keywordColor),
                    rule(#"(?m)^\s*[-*+]\s.+$"#, color: accentColor),
                    rule(#"(?m)^\s*\d+\.\s.+$"#, color: accentColor),
                    rule(#"\[[^\]]+\]\([^)]+\)"#, color: propertyColor),
                ]
            )
        case .shell:
            return Definition(
                protectedRules: [
                    rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: stringColor),
                    rule(#"#.*$"#, color: commentColor, options: [.anchorsMatchLines]),
                ],
                regularRules: [
                    keywordRule(["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "in"], color: keywordColor),
                    rule(#"\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}"#, color: accentColor),
                    rule(#"\b\d+(?:\.\d+)?\b"#, color: numberColor),
                ]
            )
        }
    }

    private static func keywordRule(_ keywords: [String], color: NSColor, options: NSRegularExpression.Options = []) -> Rule {
        let escapedKeywords = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return rule("\\b(?:\(escapedKeywords))\\b", color: color, options: options)
    }

    private static func rule(_ pattern: String, color: NSColor, options: NSRegularExpression.Options = []) -> Rule {
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: options), color: color)
    }

    private static func matches(for rule: Rule, in text: String) -> [NSRange] {
        let searchRange = NSRange(location: 0, length: (text as NSString).length)
        return rule.regex.matches(in: text, options: [], range: searchRange).map(\.range)
    }

    private static func overlapsProtected(_ candidate: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange(candidate, $0).length > 0 }
    }
}

private struct SVGPreviewView: NSViewRepresentable {
    let url: URL
    let reloadToken: Date?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        loadSVG(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.url != url || context.coordinator.reloadToken != reloadToken else { return }
        loadSVG(in: webView, context: context)
    }

    private func loadSVG(in webView: WKWebView, context: Context) {
        context.coordinator.url = url
        context.coordinator.reloadToken = reloadToken
        guard let data = try? Data(contentsOf: url) else {
            webView.loadHTMLString("<html><body style=\"margin:0;font:12px -apple-system;color:#666;display:flex;align-items:center;justify-content:center;\">Unable to load SVG</body></html>", baseURL: nil)
            return
        }

        webView.load(
            data,
            mimeType: "image/svg+xml",
            characterEncodingName: "utf-8",
            baseURL: url.deletingLastPathComponent()
        )
    }

    final class Coordinator {
        var url: URL?
        var reloadToken: Date?
    }
}

private struct ZoomableImageView: NSViewRepresentable {
    let nsImage: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var steadyZoomScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1.0
        scrollView.maxMagnification = 10.0
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.usesPredominantAxisScrolling = false

        let imageView = ImageDocumentView(image: nsImage)
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = imageView

        context.coordinator.scrollView = scrollView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationDidEnd(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? ImageDocumentView else { return }

        if imageView.image !== nsImage {
            imageView.image = nsImage
            imageView.needsDisplay = true
        }

        // Reset magnification only on file change (zoomScale reset to 1.0 by parent)
        if zoomScale == 1.0 && scrollView.magnification != 1.0 {
            scrollView.magnification = 1.0
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    class Coordinator {
        var parent: ZoomableImageView
        weak var scrollView: NSScrollView?

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        @objc func magnificationDidEnd(_ notification: Notification) {
            guard let scrollView else { return }
            parent.zoomScale = scrollView.magnification
            parent.steadyZoomScale = scrollView.magnification
        }
    }
}

private class ImageDocumentView: NSView {
    var image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = NSPoint(
            x: (viewSize.width - scaledSize.width) / 2,
            y: (viewSize.height - scaledSize.height) / 2
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: origin, size: scaledSize))
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
