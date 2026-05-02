import SwiftUI

/// Popover that hosts a tag picker for one or more selected files.
/// Computes the union (and per-file intersection) of tags across the
/// selection, lets the user edit, and writes the diff back via `TagService`.
struct TagPickerPopover: View {
    let urls: Set<URL>
    var onClose: () -> Void = {}

    @State private var workingTags: [FileTag] = []
    @State private var initialTagsByURL: [URL: Set<FileTag>] = [:]
    @State private var didLoad: Bool = false
    @State private var errorMessage: String?

    private let tagService = TagService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TagPickerTokenField(
                tags: $workingTags,
                availableTags: tagService.availableTags,
                onCommit: { newTags in
                    workingTags = newTags
                    applyDiff(newTags: newTags)
                }
            )
            .frame(minWidth: 220, minHeight: 28)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
        .onAppear { loadInitial() }
    }

    private func loadInitial() {
        guard !didLoad else { return }
        didLoad = true
        var byURL: [URL: Set<FileTag>] = [:]
        for url in urls {
            byURL[url] = Set(tagService.tags(for: url))
        }
        initialTagsByURL = byURL

        let union = byURL.values.reduce(into: Set<FileTag>()) { $0.formUnion($1) }
        workingTags = union.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func applyDiff(newTags: [FileTag]) {
        errorMessage = nil
        let newSet = Set(newTags)
        for (url, prior) in initialTagsByURL {
            let added = newSet.subtracting(prior)
            let removed = prior.subtracting(newSet)
            if added.isEmpty && removed.isEmpty { continue }

            var current = tagService.tags(for: url)
            for tag in removed {
                current.removeAll { $0 == tag }
            }
            for tag in added {
                if !current.contains(tag) { current.append(tag) }
            }
            do {
                try tagService.setTags(current, on: [url])
            } catch let error as TagWriteError {
                if errorMessage == nil {
                    errorMessage = error.localizedDescription
                }
            } catch {
                if errorMessage == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
        var byURL: [URL: Set<FileTag>] = [:]
        for url in urls {
            byURL[url] = Set(tagService.tags(for: url))
        }
        initialTagsByURL = byURL
    }
}
