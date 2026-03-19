import SwiftUI

struct FileItemIconView: View {
    let item: FileItem
    var resolveDeferredIcon: Bool = true

    @State private var icon: NSImage

    init(item: FileItem, resolveDeferredIcon: Bool = true) {
        self.item = item
        self.resolveDeferredIcon = resolveDeferredIcon
        _icon = State(initialValue: item.icon)
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .task(id: item.id) {
                await refreshIcon()
            }
    }

    private func refreshIcon() async {
        await MainActor.run {
            icon = item.icon
            guard resolveDeferredIcon, item.deferredIconURL != nil else { return }
            icon = FileIconProvider.shared.icon(for: item)
        }
    }
}
