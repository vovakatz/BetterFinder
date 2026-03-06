import SwiftUI

struct GitWidgetView: View {
    let currentDirectory: URL
    @Binding var widgetType: WidgetType
    @State private var gitService = GitService()
    @State private var commitMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeaderView(widgetType: $widgetType) {
                Button {
                    gitService.refresh(for: currentDirectory)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)

            if gitService.repoRoot == nil {
                notARepoView
            } else {
                repoContentView
            }
        }
        .task(id: currentDirectory) {
            gitService.refresh(for: currentDirectory)
        }
    }

    // MARK: - Not a Repo

    private var notARepoView: some View {
        VStack {
            Spacer()
            Text("Not a Git Repository")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Repo Content

    private var repoContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                branchRow
                Divider()
                changesSection
                Divider()
                commitSection
                Divider()
                commitsSection
            }
        }
    }

    // MARK: - Branch

    private var branchRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(gitService.currentBranch)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            if gitService.hasRemote {
                if gitService.aheadCount > 0 {
                    Text("\(gitService.aheadCount)↑")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                if gitService.behindCount > 0 {
                    Text("\(gitService.behindCount)↓")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Changes

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Changes", count: gitService.statusEntries.count)

            if gitService.statusEntries.isEmpty {
                Text("No changes")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(gitService.statusEntries) { entry in
                    statusRow(entry)
                }

                HStack(spacing: 6) {
                    Button("Stage All") {
                        gitService.stageAll()
                    }
                    .disabled(gitService.unstagedEntries.isEmpty)

                    Button("Unstage All") {
                        gitService.unstageAll()
                    }
                    .disabled(gitService.stagedEntries.isEmpty)
                }
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func statusRow(_ entry: GitStatusEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.status.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(colorForStatus(entry.status))
                .frame(width: 14, alignment: .center)

            Text(entry.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                if entry.isStaged {
                    gitService.unstageFile(path: entry.path)
                } else {
                    gitService.stageFile(path: entry.path)
                }
            } label: {
                Image(systemName: entry.isStaged ? "minus.circle" : "plus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isStaged ? .orange : .green)
            }
            .buttonStyle(.plain)
            .help(entry.isStaged ? "Unstage" : "Stage")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Commit

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Commit (\(gitService.stagedEntries.count))") {
                    if gitService.commit(message: commitMessage) {
                        commitMessage = ""
                    }
                }
                .controlSize(.small)
                .disabled(gitService.stagedEntries.isEmpty || commitMessage.isEmpty)

                if gitService.hasRemote {
                    Button {
                        gitService.push()
                    } label: {
                        HStack(spacing: 3) {
                            if gitService.isPushing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.6)
                            }
                            Text("Push")
                            if gitService.aheadCount > 0 {
                                Text("(\(gitService.aheadCount))")
                            }
                        }
                    }
                    .controlSize(.small)
                    .disabled(gitService.aheadCount == 0 || gitService.isPushing)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Recent Commits

    private var commitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent Commits", count: nil)

            if gitService.recentCommits.isEmpty {
                Text("No commits yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(gitService.recentCommits) { commit in
                    commitRow(commit)
                }
            }
        }
    }

    private func commitRow(_ commit: GitCommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(commit.shortHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 4) {
                Text(commit.author)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(commit.relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let count {
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func colorForStatus(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .gray
        case .conflicted: return .purple
        }
    }
}
