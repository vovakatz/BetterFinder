import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show hidden files by default", isOn: $settings.showHiddenFilesByDefault)
            } footer: {
                Text("New windows and panes will show files whose names start with a dot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Folder on Launch") {
                Picker("Open to:", selection: $settings.defaultLocation) {
                    ForEach(DefaultLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.menu)

                if settings.defaultLocation == .custom {
                    HStack {
                        Text("Folder:")
                        Text(displayPath(settings.customDefaultLocationPath))
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { chooseCustomFolder() }
                    }
                }
            }

            Section {
                Picker("Sort by:", selection: $settings.defaultSortCriteria.field) {
                    Text("Name").tag(SortField.name)
                    Text("Date Modified").tag(SortField.dateModified)
                    Text("Size").tag(SortField.size)
                    Text("Kind").tag(SortField.kind)
                }
                .pickerStyle(.menu)

                LabeledContent("Order:") {
                    HStack {
                        Spacer()
                        Picker("", selection: $settings.defaultSortCriteria.ascending) {
                            Text("Ascending").tag(true)
                            Text("Descending").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            } header: {
                Text("Default Sort")
            } footer: {
                Text("Applies to folders that don't already have a remembered sort order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func displayPath(_ path: String) -> String {
        if path.isEmpty { return "(none selected)" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if !settings.customDefaultLocationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.customDefaultLocationPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.customDefaultLocationPath = url.path
        }
    }
}
