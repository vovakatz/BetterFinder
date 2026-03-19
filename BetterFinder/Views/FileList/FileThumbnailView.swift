import SwiftUI
import QuickLookThumbnailing

struct FileThumbnailView: View {
    let item: FileItem
    let isSelected: Bool
    var isRenaming: Bool = false
    @Binding var renameText: String
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    FileItemIconView(item: item, resolveDeferredIcon: false)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if isRenaming {
                RenameTextField(
                    text: $renameText,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename,
                    fontSize: 11
                )
                .frame(width: 100)
            } else {
                Text(item.name)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !item.isDirectory {
                Text(item.fileSizeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 110)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 160, height: 160),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.nsImage
        } catch {
            // Keep the system icon as fallback
        }
    }
}
