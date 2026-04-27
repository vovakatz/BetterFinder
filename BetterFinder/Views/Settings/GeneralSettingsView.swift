import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginErrorMessage: String?
    @State private var isDefaultFolderHandler: Bool = DefaultFolderHandlerService.isDefault
    @State private var defaultHandlerErrorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch BetterFinder at login", isOn: $launchAtLogin)
                Toggle("Show hidden files by default", isOn: $settings.showHiddenFilesByDefault)
            } footer: {
                Text("New windows and panes will show files whose names start with a dot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Set as the default file browser", isOn: $isDefaultFolderHandler)
            } footer: {
                Text("Folders opened from Terminal and other apps will open in BetterFinder instead of Finder. \"Reveal in Finder\" actions in other apps still go to Finder.")
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
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
            isDefaultFolderHandler = DefaultFolderHandlerService.isDefault
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                try LaunchAtLoginService.setEnabled(newValue)
            } catch {
                launchAtLoginErrorMessage = error.localizedDescription
                launchAtLogin = LaunchAtLoginService.isEnabled
            }
        }
        .onChange(of: isDefaultFolderHandler) { _, newValue in
            let status = DefaultFolderHandlerService.setDefault(newValue)
            if status != noErr {
                defaultHandlerErrorMessage = "LaunchServices returned status \(status). Try moving BetterFinder to /Applications and re-launching."
                isDefaultFolderHandler = DefaultFolderHandlerService.isDefault
            }
        }
        .alert(
            "Could not update login item",
            isPresented: Binding(
                get: { launchAtLoginErrorMessage != nil },
                set: { if !$0 { launchAtLoginErrorMessage = nil } }
            ),
            presenting: launchAtLoginErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { launchAtLoginErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "Could not update default folder handler",
            isPresented: Binding(
                get: { defaultHandlerErrorMessage != nil },
                set: { if !$0 { defaultHandlerErrorMessage = nil } }
            ),
            presenting: defaultHandlerErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { defaultHandlerErrorMessage = nil }
        } message: { message in
            Text(message)
        }
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
