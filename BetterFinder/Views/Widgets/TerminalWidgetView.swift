import SwiftUI

struct TerminalWidgetView: View {
    let currentDirectory: URL
    @Binding var widgetType: WidgetType
    @State private var session = TerminalSession()
    @AppStorage("terminalTheme") private var theme: TerminalTheme = .default
    @State private var pathFollowing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeaderView(widgetType: $widgetType, leadingButtons: {
                Toggle("Auto Sync", isOn: $pathFollowing)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(TerminalTheme.allCases) { t in
                        Button {
                            theme = t
                        } label: {
                            if t == theme {
                                Label(t.rawValue, systemImage: "checkmark")
                            } else {
                                Text(t.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }, extraButtons: {
                Button {
                    session.clearTerminal()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            })
            .fixedSize(horizontal: false, vertical: true)

            TerminalEmulatorView(session: session, initialDirectory: currentDirectory, theme: theme)
        }
        .onChange(of: currentDirectory) { _, newVal in
            if pathFollowing {
                session.changeDirectory(to: newVal)
            }
        }
        .onChange(of: pathFollowing) { _, isFollowing in
            if isFollowing {
                session.changeDirectory(to: currentDirectory)
            }
        }
        .onDisappear {
            session.stop()
        }
    }
}
