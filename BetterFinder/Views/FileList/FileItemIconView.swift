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
        Image(nsImage: tintedIfNeeded(icon))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .task(id: item.id) {
                await refreshIcon()
            }
    }

    /// Tints folder icons with the primary tag color when the item has
    /// any colored tag, mirroring Finder's behavior. Non-folders and
    /// untagged items render unchanged.
    private func tintedIfNeeded(_ base: NSImage) -> NSImage {
        guard item.isDirectory,
              let primary = item.tags.first(where: { !$0.color.rendersAsRing }) else {
            return base
        }
        return primary.color.tinted(base)
    }

    private func refreshIcon() async {
        await MainActor.run {
            icon = item.icon
            guard resolveDeferredIcon, item.deferredIconURL != nil else { return }
            icon = FileIconProvider.shared.icon(for: item)
        }
    }
}
