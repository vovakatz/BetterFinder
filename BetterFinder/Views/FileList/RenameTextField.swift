import SwiftUI
import AppKit

struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var fontSize: CGFloat = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let cell = CompactTextFieldCell(textCell: text)
        cell.font = .systemFont(ofSize: fontSize)
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.lineBreakMode = .byClipping

        let field = NSTextField(frame: .zero)
        field.cell = cell
        field.stringValue = text
        field.font = .systemFont(ofSize: fontSize)
        field.isBordered = true
        field.isBezeled = false
        field.backgroundColor = .white
        field.drawsBackground = true
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.wantsLayer = true
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.separatorColor.cgColor

        field.setContentHuggingPriority(.defaultHigh, for: .vertical)

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                let name = text
                let stemEnd = Self.stemLength(of: name)
                editor.setSelectedRange(NSRange(location: 0, length: stemEnd))
                editor.textContainerInset = NSSize(width: 0, height: 0)
            }
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    private static func stemLength(of name: String) -> Int {
        guard let dotIndex = name.lastIndex(of: "."),
              dotIndex != name.startIndex,
              dotIndex != name.index(before: name.endIndex) else {
            return name.count
        }
        return name.distance(from: name.startIndex, to: dotIndex)
    }

    class CompactTextFieldCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            let font = self.font ?? .systemFont(ofSize: 12)
            let fontHeight = ceil(font.ascender - font.descender + font.leading)
            let y = (rect.height - fontHeight) / 2
            return NSRect(x: rect.origin.x + 2, y: y, width: rect.width - 4, height: fontHeight)
        }

        override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
            super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        }

        override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
            super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // When the text field loses focus (user clicked elsewhere), commit the rename.
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
