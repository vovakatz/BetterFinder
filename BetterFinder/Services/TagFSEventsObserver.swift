import Foundation
import CoreServices

/// Watches a single directory for extended-attribute modifications and
/// reports per-file changes. Used to pick up tag changes made by Finder
/// or other apps while BetterFinder is showing the same folder.
final class TagFSEventsObserver {
    private var stream: FSEventStreamRef?
    var onXattrChange: ((URL) -> Void)?

    func start(watching directory: URL) {
        stop()

        let pathsToWatch = [directory.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, contextInfo, numEvents, eventPaths, eventFlags, _ in
            guard let contextInfo else { return }
            let observer = Unmanaged<TagFSEventsObserver>.fromOpaque(contextInfo).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            for i in 0..<numEvents {
                let flags = eventFlags[i]
                if flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
                    let path = paths[i]
                    let url = URL(fileURLWithPath: path)
                    DispatchQueue.main.async {
                        observer.onXattrChange?(url)
                    }
                }
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
