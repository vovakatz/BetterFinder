import SwiftUI

/// The toolbar slot for copy/move progress. It reads the queue itself, so
/// progress ticks redraw only this slot, not the whole window.
struct ToolbarTransferProgressSlot: View {
    static let height: CGFloat = 24
    private static let visibleWidth: CGFloat = 200
    private static let visibleWidthWithQueue: CGFloat = 236

    let queue: FileOperationQueue
    @State private var showQueue = false

    private var width: CGFloat {
        guard queue.progress != nil else { return 0 }
        return queue.pending.isEmpty ? Self.visibleWidth : Self.visibleWidthWithQueue
    }

    var body: some View {
        Group {
            if let progress = queue.progress {
                ToolbarTransferProgressView(
                    progress: progress,
                    queuedCount: queue.pending.count,
                    onShowQueue: { showQueue.toggle() },
                    onCancel: { queue.cancelCurrent() }
                )
                .popover(isPresented: $showQueue, arrowEdge: .bottom) {
                    FileOperationQueuePopover(queue: queue)
                }
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: Self.height, alignment: .leading)
    }
}

private struct ToolbarTransferProgressView: View {
    let progress: FileOperationProgress
    let queuedCount: Int
    let onShowQueue: () -> Void
    let onCancel: () -> Void

    private var labelText: String {
        guard let detail = progress.detail, !detail.isEmpty, detail != progress.title else {
            return progress.title
        }
        return detail
    }

    private var helpText: String {
        let base = progress.detail ?? progress.title
        guard queuedCount > 0 else { return base }
        return "\(base)\n\(queuedCount) more waiting. Click to see the queue."
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

            if queuedCount > 0 {
                Text("+\(queuedCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(Capsule().fill(Color.accentColor))
                    .accessibilityLabel("\(queuedCount) more waiting")

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

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
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture(perform: onShowQueue)
        .help(helpText)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show queue", onShowQueue)
    }
}

/// The dropdown under the pill: the running operation, then the waiting
/// ones in the order they'll run.
private struct FileOperationQueuePopover: View {
    private static let maxPendingListHeight: CGFloat = 320

    let queue: FileOperationQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = queue.current {
                sectionHeader("Now")
                RunningOperationRow(
                    operation: current,
                    progress: queue.progress,
                    onCancel: { queue.cancelCurrent() }
                )
            }

            if !queue.pending.isEmpty {
                Divider()
                    .padding(.top, 4)
                sectionHeader("Up Next")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(queue.pending.enumerated()), id: \.element.id) { index, operation in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                            PendingOperationRow(
                                operation: operation,
                                onRemove: { queue.removePending(id: operation.id) }
                            )
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Self.maxPendingListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 340)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct OperationIcon: View {
    let operation: FileOperationProgress.Operation

    var body: some View {
        Image(systemName: operation == .copy ? "doc.on.doc" : "arrow.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

private struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct RunningOperationRow: View {
    let operation: QueuedFileOperation
    let progress: FileOperationProgress?
    let onCancel: () -> Void

    private var statusText: String {
        guard let progress else { return "Preparing..." }
        guard progress.totalUnitCount > 0 else { return progress.detail ?? "Preparing..." }
        let completed = min(progress.completedUnitCount, progress.totalUnitCount)
        let counts = "\(completed) of \(progress.totalUnitCount)"
        guard let detail = progress.detail, !detail.isEmpty else { return counts }
        return "\(counts) · \(detail)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OperationIcon(operation: operation.operation)

            VStack(alignment: .leading, spacing: 4) {
                Text(operation.runningTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Group {
                    if let fraction = progress?.fractionCompleted {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .controlSize(.small)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RemoveButton(help: "Cancel \(operation.operation.infinitive)", action: onCancel)
                .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PendingOperationRow: View {
    let operation: QueuedFileOperation
    let onRemove: () -> Void

    private var statusText: String {
        guard let folder = operation.sourceFolderName else { return "Waiting" }
        return "Waiting · from \(folder)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OperationIcon(operation: operation.operation)

            VStack(alignment: .leading, spacing: 2) {
                Text(operation.pendingTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RemoveButton(help: "Remove from queue", action: onRemove)
                .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(operation.sources.map(\.lastPathComponent).joined(separator: "\n"))
    }
}
