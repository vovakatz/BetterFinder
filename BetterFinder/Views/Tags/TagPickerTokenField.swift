import SwiftUI
import AppKit

/// SwiftUI wrapper around `NSTokenField` that displays each token as a
/// colored dot + name, with autocomplete sourced from the current tag
/// catalog. Editing commits the new tag list via the `onCommit` closure.
struct TagPickerTokenField: NSViewRepresentable {
    /// The current tag list. Bound so external changes (selection
    /// replaced, etc.) reset the field.
    @Binding var tags: [FileTag]

    /// Available tags for autocomplete.
    let availableTags: [FileTag]

    /// Called when the user commits a change (Return, blur, or token
    /// add/remove). Receives the new tag list.
    var onCommit: ([FileTag]) -> Void = { _ in }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.tokenStyle = .rounded
        field.delegate = context.coordinator
        field.completionDelay = 0.1
        field.font = .systemFont(ofSize: 11)
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        field.objectValue = tags.map(\.name)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        let currentNames = (field.objectValue as? [String]) ?? []
        let desiredNames = tags.map(\.name)
        if currentNames != desiredNames {
            field.objectValue = desiredNames
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: TagPickerTokenField

        init(parent: TagPickerTokenField) {
            self.parent = parent
        }

        // Autocomplete from the catalog.
        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            let matches = parent.availableTags
                .map(\.name)
                .filter { $0.localizedCaseInsensitiveContains(substring) }
            return matches
        }

        // Commit on every change (token added or removed).
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTokenField else { return }
            commit(field)
        }

        // Commit on blur and Return.
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTokenField else { return }
            commit(field)
        }

        private func commit(_ field: NSTokenField) {
            let names = (field.objectValue as? [String]) ?? []
            let resolved = names.map { name -> FileTag in
                if let known = parent.availableTags.first(where: { $0.name == name }) {
                    return known
                }
                return FileTag(name: name, color: .none)
            }
            parent.onCommit(resolved)
        }
    }
}
