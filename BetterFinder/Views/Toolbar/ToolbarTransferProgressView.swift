import SwiftUI

struct ToolbarTransferProgressSlot: View {
    static let height: CGFloat = 24
    private static let visibleWidth: CGFloat = 200

    let progress: FileOperationProgress?
    let onCancel: () -> Void

    var body: some View {
        Group {
            if let progress {
                ToolbarTransferProgressView(progress: progress, onCancel: onCancel)
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: progress == nil ? 0 : Self.visibleWidth,
            height: Self.height,
            alignment: .leading
        )
    }
}

private struct ToolbarTransferProgressView: View {
    let progress: FileOperationProgress
    let onCancel: () -> Void

    private var labelText: String {
        guard let detail = progress.detail, !detail.isEmpty, detail != progress.title else {
            return progress.title
        }
        return detail
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .controlSize(.small)
            .frame(width: 50)

            Text(labelText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel \(progress.operation.infinitive)")
        }
        .padding(.horizontal, 8)
        .frame(height: ToolbarTransferProgressSlot.height)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .help(progress.detail ?? progress.title)
    }
}
