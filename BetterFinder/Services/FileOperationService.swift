import Foundation

struct FileOperationProgress: Sendable {
    enum Operation: Sendable {
        case copy
        case move

        nonisolated var infinitive: String {
            switch self {
            case .copy:
                return "copy"
            case .move:
                return "move"
            }
        }

        nonisolated var presentParticiple: String {
            switch self {
            case .copy:
                return "Copying"
            case .move:
                return "Moving"
            }
        }
    }

    let operation: Operation
    let completedUnitCount: Int
    let totalUnitCount: Int
    let currentItemName: String?
    let statusMessage: String?

    var fractionCompleted: Double? {
        guard totalUnitCount > 0 else { return nil }
        let progress = Double(completedUnitCount) / Double(totalUnitCount)
        return min(1, max(0, progress))
    }

    var title: String {
        guard totalUnitCount > 0 else {
            return "\(operation.presentParticiple)..."
        }

        let completed = min(completedUnitCount, totalUnitCount)
        let noun = totalUnitCount == 1 ? "item" : "items"
        return "\(operation.presentParticiple) \(completed) of \(totalUnitCount) \(noun)"
    }

    var detail: String? {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        if let currentItemName, !currentItemName.isEmpty {
            return currentItemName
        }
        return nil
    }
}

struct FileOperationResult: Sendable {
    let completedSources: Set<URL>
    let errors: [String]

    var allSucceeded: Bool {
        errors.isEmpty
    }
}

struct FileOperationService: Sendable {
    private enum PlannedNodeKind {
        case directory
        case item
    }

    private struct PlannedNode {
        let source: URL
        let destination: URL
        let kind: PlannedNodeKind
    }

    private struct RootPlan: Sendable {
        let source: URL
        let destination: URL
        let nodes: [PlannedNode]
        let usesDirectMove: Bool
        let requiresCleanup: Bool
        let progressUnitCount: Int
    }

    private enum FileOperationError: LocalizedError {
        case destinationInsideSource

        var errorDescription: String? {
            switch self {
            case .destinationInsideSource:
                return "You can't copy or move a folder into itself."
            }
        }
    }

    nonisolated func execute(
        sources: [URL],
        to destinationDirectory: URL,
        operation: FileOperationProgress.Operation,
        overwrite: Bool = false,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (FileOperationProgress) -> Void
    ) -> FileOperationResult {
        let fileManager = FileManager.default
        let sortedSources = sources.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        var completedSources: Set<URL> = []
        var errors: [String] = []
        var plans: [RootPlan] = []

        for source in sortedSources {
            do {
                plans.append(try makePlan(
                    for: source,
                    destinationDirectory: destinationDirectory,
                    operation: operation
                ))
            } catch {
                errors.append(errorMessage(for: operation, source: source, error: error))
            }
        }

        let totalUnitCount = plans.reduce(0) { $0 + $1.progressUnitCount }
        var completedUnitCount = 0

        progress(FileOperationProgress(
            operation: operation,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            currentItemName: nil,
            statusMessage: "Preparing..."
        ))

        planLoop: for plan in plans {
            if isCancelled() { break }

            do {
                if overwrite && fileManager.fileExists(atPath: plan.destination.path) {
                    try fileManager.removeItem(at: plan.destination)
                }

                if plan.usesDirectMove {
                    try fileManager.moveItem(at: plan.source, to: plan.destination)
                    completedUnitCount += plan.progressUnitCount
                    progress(FileOperationProgress(
                        operation: operation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemName: plan.source.lastPathComponent,
                        statusMessage: nil
                    ))
                    completedSources.insert(plan.source)
                    continue
                }

                for node in plan.nodes {
                    if isCancelled() {
                        try? cleanupPartialTransfer(at: plan.destination, fileManager: fileManager)
                        break planLoop
                    }

                    switch node.kind {
                    case .directory:
                        try fileManager.createDirectory(at: node.destination, withIntermediateDirectories: true)
                    case .item:
                        let parentDirectory = node.destination.deletingLastPathComponent()
                        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
                        try fileManager.copyItem(at: node.source, to: node.destination)
                    }

                    completedUnitCount += 1
                    progress(FileOperationProgress(
                        operation: operation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemName: node.source.lastPathComponent,
                        statusMessage: nil
                    ))
                }

                if isCancelled() { break }

                if plan.requiresCleanup {
                    progress(FileOperationProgress(
                        operation: operation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemName: nil,
                        statusMessage: "Cleaning up originals..."
                    ))
                    try fileManager.removeItem(at: plan.source)
                    completedUnitCount += 1
                    progress(FileOperationProgress(
                        operation: operation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemName: plan.source.lastPathComponent,
                        statusMessage: nil
                    ))
                }

                completedSources.insert(plan.source)
            } catch {
                if !plan.usesDirectMove {
                    try? cleanupPartialTransfer(at: plan.destination, fileManager: fileManager)
                }
                errors.append(errorMessage(for: operation, source: plan.source, error: error))
            }
        }

        return FileOperationResult(completedSources: completedSources, errors: errors)
    }

    private nonisolated func makePlan(
        for source: URL,
        destinationDirectory: URL,
        operation: FileOperationProgress.Operation
    ) throws -> RootPlan {
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values.isDirectory ?? false

        if isDirectory && isSameOrDescendant(destination, of: source) {
            throw FileOperationError.destinationInsideSource
        }

        let nodes = try buildNodes(
            source: source,
            destination: destination,
            isDirectory: isDirectory
        )

        let usesDirectMove = isMove(operation) && isSameVolume(source, destinationDirectory)
        let requiresCleanup = isMove(operation) && !usesDirectMove

        return RootPlan(
            source: source,
            destination: destination,
            nodes: nodes,
            usesDirectMove: usesDirectMove,
            requiresCleanup: requiresCleanup,
            progressUnitCount: nodes.count + (requiresCleanup ? 1 : 0)
        )
    }

    private nonisolated func buildNodes(source: URL, destination: URL, isDirectory: Bool? = nil) throws -> [PlannedNode] {
        let fileManager = FileManager.default
        let directory: Bool
        if let isDirectory {
            directory = isDirectory
        } else {
            directory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        }

        guard directory else {
            return [PlannedNode(source: source, destination: destination, kind: .item)]
        }

        var nodes: [PlannedNode] = [
            PlannedNode(source: source, destination: destination, kind: .directory)
        ]

        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for child in children {
            let childDestination = destination.appendingPathComponent(child.lastPathComponent)
            let childIsDirectory = (try child.resourceValues(forKeys: [.isDirectoryKey])).isDirectory ?? false
            nodes.append(contentsOf: try buildNodes(
                source: child,
                destination: childDestination,
                isDirectory: childIsDirectory
            ))
        }

        return nodes
    }

    private nonisolated func cleanupPartialTransfer(at destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try fileManager.removeItem(at: destination)
    }

    private nonisolated func isSameVolume(_ source: URL, _ destinationDirectory: URL) -> Bool {
        let sourceIdentifier = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let destinationIdentifier = try? destinationDirectory.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject

        guard let sourceIdentifier, let destinationIdentifier else {
            return false
        }

        return sourceIdentifier == destinationIdentifier
    }

    private nonisolated func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path(percentEncoded: false)
        let ancestorPath = ancestor.standardizedFileURL.path(percentEncoded: false)
        return candidatePath == ancestorPath || candidatePath.hasPrefix(ancestorPath + "/")
    }

    private nonisolated func errorMessage(
        for operation: FileOperationProgress.Operation,
        source: URL,
        error: Error
    ) -> String {
        "Couldn't \(operation.infinitive) \"\(source.lastPathComponent)\": \(error.localizedDescription)"
    }

    private nonisolated func isMove(_ operation: FileOperationProgress.Operation) -> Bool {
        switch operation {
        case .copy:
            return false
        case .move:
            return true
        }
    }
}
