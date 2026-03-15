import SwiftUI

struct ToolbarView: View {
    let pathComponents: [(name: String, url: URL)]
    let onNavigate: (URL) -> Void
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var onGoBack: () -> Void = {}
    var onGoForward: () -> Void = {}
    var onNewFolder: () -> Void = {}
    var onNewFile: () -> Void = {}
    @Binding var viewMode: ViewMode
    @Binding var showHiddenFiles: Bool
    var onToggleHiddenFiles: () -> Void = {}

    @State private var isEditingPath = false
    @State private var editablePath = ""
    private var currentDirectoryPath: String {
        pathComponents.last?.url.path ?? "/"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onGoBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)

            Button(action: onGoForward) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!canGoForward)

            Spacer()

            if isEditingPath {
                PathEditField(
                    text: $editablePath,
                    onCommit: {
                        commitPathEdit()
                    },
                    onCancel: {
                        isEditingPath = false
                    }
                )
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                BreadcrumbItem(
                                    name: component.name,
                                    isCurrent: index == pathComponents.count - 1
                                ) {
                                    if index == pathComponents.count - 1 {
                                        enterPathEditing()
                                    } else {
                                        onNavigate(component.url)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    enterPathEditing()
                }
            }

            Button { viewMode = .list } label: {
                Image(systemName: "list.dash")
                    .foregroundStyle(viewMode == .list ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("List view")

            Button { viewMode = .thumbnails } label: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(viewMode == .thumbnails ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Thumbnail view")

            Button(action: onToggleHiddenFiles) {
                Image(systemName: showHiddenFiles ? "eye" : "eye.slash")
                    .foregroundStyle(showHiddenFiles ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            Button(action: onNewFile) {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New File")
            .padding(.leading, 6)

            Button(action: onNewFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New Folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3.5)
    }

    private func enterPathEditing() {
        editablePath = currentDirectoryPath
        isEditingPath = true
    }

    private func commitPathEdit() {
        let trimmed = editablePath.trimmingCharacters(in: .whitespaces)
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardized
        isEditingPath = false
        if url.path != currentDirectoryPath {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                onNavigate(url)
            } else {
                NSSound.beep()
            }
        }
    }
}

private struct PathEditField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 11)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior
        field.delegate = context.coordinator
        field.stringValue = text
        // Become first responder and select all text on next run loop
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PathEditField

        init(_ parent: PathEditField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // Check if ended by pressing Enter (return key)
            if let movement = obj.userInfo?["NSTextMovement"] as? Int,
               movement == NSReturnTextMovement {
                parent.onCommit()
            } else {
                parent.onCancel()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

private struct BreadcrumbItem: View {
    let name: String
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.black.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
