import Foundation

/// A copy or move request, either waiting in a `FileOperationQueue` or running.
struct QueuedFileOperation: Identifiable {
    let id = UUID()
    let sources: [URL]
    let destination: URL
    let operation: FileOperationProgress.Operation
    let overwrite: Bool
    /// Called on the main actor once the operation has run, including after a
    /// cancel. Not called for an operation removed from the queue before it started.
    let onFinish: (FileOperationResult) -> Void

    /// "“Vacation 2025”" for a single item, "3 items" otherwise.
    private var itemsPhrase: String {
        if sources.count == 1, let only = sources.first {
            return "“\(only.lastPathComponent)”"
        }
        return "\(sources.count) items"
    }

    private var destinationName: String {
        "“\(destination.lastPathComponent)”"
    }

    /// "Copy 3 items to “Archive”"
    var pendingTitle: String {
        "\(operation.imperative) \(itemsPhrase) to \(destinationName)"
    }

    /// "Copying 3 items to “Archive”"
    var runningTitle: String {
        "\(operation.presentParticiple) \(itemsPhrase) to \(destinationName)"
    }

    /// The folder the sources came from, when they all share one.
    var sourceFolderName: String? {
        let parents = Set(sources.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard parents.count == 1, let parent = parents.first else { return nil }
        return parent.lastPathComponent
    }
}

/// Runs one window's copy and move operations one at a time, in the order
/// they were requested, on a background task.
@Observable
final class FileOperationQueue {
    private(set) var current: QueuedFileOperation?
    private(set) var progress: FileOperationProgress?
    private(set) var pending: [QueuedFileOperation] = []

    @ObservationIgnored private let service = FileOperationService()
    @ObservationIgnored private var task: Task<Void, Never>?

    deinit {
        // The window that owned this queue closed. Stop the running
        // operation, as the per-pane task did before the queue existed.
        task?.cancel()
    }

    func enqueue(
        sources: [URL],
        destination: URL,
        operation: FileOperationProgress.Operation,
        overwrite: Bool,
        onFinish: @escaping (FileOperationResult) -> Void
    ) {
        guard !sources.isEmpty else { return }
        pending.append(QueuedFileOperation(
            sources: sources,
            destination: destination,
            operation: operation,
            overwrite: overwrite,
            onFinish: onFinish
        ))
        startNextIfIdle()
    }

    /// Cancels the running operation. The next queued one starts once the
    /// cancelled one has stopped and cleaned up.
    func cancelCurrent() {
        task?.cancel()
    }

    func removePending(id: QueuedFileOperation.ID) {
        pending.removeAll { $0.id == id }
    }

    private func startNextIfIdle() {
        guard current == nil, !pending.isEmpty else { return }

        let next = pending.removeFirst()
        current = next
        progress = FileOperationProgress(
            operation: next.operation,
            completedUnitCount: 0,
            totalUnitCount: 0,
            currentItemName: nil,
            statusMessage: "Preparing..."
        )

        let service = service
        let id = next.id
        let sources = next.sources
        let destination = next.destination
        let operation = next.operation
        let overwrite = next.overwrite

        task = Task.detached(priority: .utility) { [weak self] in
            let result = service.execute(
                sources: sources,
                to: destination,
                operation: operation,
                overwrite: overwrite,
                isCancelled: { Task.isCancelled }
            ) { progress in
                DispatchQueue.main.async {
                    // A tick can land after `finish` has moved on to the next operation.
                    guard let self, self.current?.id == id else { return }
                    self.progress = progress
                }
            }

            await self?.finish(id: id, result: result)
        }
    }

    private func finish(id: QueuedFileOperation.ID, result: FileOperationResult) {
        guard let finished = current, finished.id == id else { return }
        current = nil
        progress = nil
        task = nil
        finished.onFinish(result)
        startNextIfIdle()
    }
}
