import SwiftUI

private struct EjectButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "eject.fill")
                .font(.system(size: 10))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.15 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Binding var selection: URL?
    var onEmptyTrash: () -> Void = {}
    @State private var showEmptyTrashConfirmation = false

    var body: some View {
        List(selection: $selection) {
            Section(header: Text("Favorites").fontWeight(.bold)) {
                ForEach(viewModel.favorites) { item in
                    Label(item.name, systemImage: item.icon)
                        .tag(item.url)
                        .contextMenu {
                            if item.isTrash {
                                Button("Empty Trash") {
                                    showEmptyTrashConfirmation = true
                                }

                                Divider()
                            }

                            Button("Remove") {
                                viewModel.removeFavorite(item)
                            }
                            .disabled(item.isDefault)
                        }
                }
                .dropDestination(for: URL.self) { urls, index in
                    for url in urls {
                        viewModel.insertFavorite(url: url, at: index)
                    }
                }
            }

            Section(header: Text("Locations").fontWeight(.bold)) {
                Label(viewModel.networkItem.name, systemImage: viewModel.networkItem.icon)
                    .tag(viewModel.networkItem.url)

                ForEach(viewModel.localVolumes) { item in
                    Label(item.name, systemImage: item.icon)
                        .tag(item.url)
                }

                ForEach(viewModel.networkVolumes) { item in
                    ejectableVolumeRow(item)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.15))
        .alert("Empty Trash?", isPresented: $showEmptyTrashConfirmation) {
            Button("Empty Trash", role: .destructive) {
                onEmptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all items in Trash. This action cannot be undone.")
        }
    }

    private func ejectableVolumeRow(_ item: SidebarItem) -> some View {
        HStack {
            Label(item.name, systemImage: item.icon)
            Spacer()
            EjectButton { ejectVolume(item.url) }
                .help("Eject \(item.name)")
        }
        .tag(item.url)
    }

    private func ejectVolume(_ url: URL) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            // Silently fail — volume may already be ejected
        }
    }
}
