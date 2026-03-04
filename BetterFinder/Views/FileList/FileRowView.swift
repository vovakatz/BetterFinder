import SwiftUI

struct FileRowView: View {
    let item: FileItem
    let dateWidth: CGFloat
    let sizeWidth: CGFloat
    let kindWidth: CGFloat
    var depth: Int = 0
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)?
    var isRenaming: Bool = false
    @Binding var renameText: String
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}
    var onNameHover: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if item.isDirectory, item.url.isFileURL {
                    Button { onToggleExpand?() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isExpanded)
                            .frame(minWidth: 16, maxWidth: 16, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 16, maxWidth: 16, maxHeight: .infinity)
                } else {
                    Spacer().frame(width: 16)
                }

                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                if isRenaming {
                    RenameTextField(
                        text: $renameText,
                        onCommit: onCommitRename,
                        onCancel: onCancelRename,
                        fontSize: 12
                    )
                    .frame(height: 18)
                } else {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .fontWeight(item.isDirectory ? .bold : .regular)
                        .foregroundStyle(item.isHidden ? .gray : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onHover { onNameHover?($0) }
                }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 8)

            Text(item.dateModified?.fileDateString ?? "--")
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: dateWidth, alignment: .leading)

            Spacer().frame(width: 8)

            Text(item.isDirectory ? "--" : item.fileSize.formattedFileSize)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: sizeWidth, alignment: .trailing)

            Spacer().frame(width: 8)

            Text(item.kind)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: kindWidth, alignment: .leading)
        }
        .font(.system(size: 12))
    }
}
