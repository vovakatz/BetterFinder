import Foundation

enum GitFileStatus: String {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"
    case conflicted = "U"
}

struct GitStatusEntry: Identifiable {
    let path: String
    let status: GitFileStatus
    let isStaged: Bool

    var id: String { "\(isStaged ? "S" : "W"):\(path)" }
}

struct GitCommitInfo: Identifiable {
    let hash: String
    let shortHash: String
    let message: String
    let author: String
    let date: Date

    var id: String { hash }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

@Observable
class GitService {
    var repoRoot: URL?
    var currentBranch: String = ""
    var statusEntries: [GitStatusEntry] = []
    var recentCommits: [GitCommitInfo] = []
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var hasRemote: Bool = false
    var isPushing = false
    var lastError: String?
    var isLoading = false

    var stagedEntries: [GitStatusEntry] {
        statusEntries.filter(\.isStaged)
    }

    var unstagedEntries: [GitStatusEntry] {
        statusEntries.filter { !$0.isStaged }
    }

    // MARK: - Refresh

    func refresh(for directory: URL) {
        isLoading = true
        lastError = nil

        let root = findRepoRoot(for: directory)
        repoRoot = root

        guard let root else {
            currentBranch = ""
            statusEntries = []
            recentCommits = []
            isLoading = false
            return
        }

        currentBranch = loadBranch(at: root)
        loadRemoteStatus(at: root)
        statusEntries = loadStatus(at: root)
        recentCommits = loadLog(at: root)
        isLoading = false
    }

    // MARK: - Write Operations

    func stageFile(path: String) {
        guard let root = repoRoot else { return }
        runGit(["add", "--", path], at: root)
        statusEntries = loadStatus(at: root)
    }

    func unstageFile(path: String) {
        guard let root = repoRoot else { return }
        runGit(["reset", "HEAD", "--", path], at: root)
        statusEntries = loadStatus(at: root)
    }

    func stageAll() {
        guard let root = repoRoot else { return }
        runGit(["add", "-A"], at: root)
        statusEntries = loadStatus(at: root)
    }

    func unstageAll() {
        guard let root = repoRoot else { return }
        runGit(["reset", "HEAD"], at: root)
        statusEntries = loadStatus(at: root)
    }

    func commit(message: String) -> Bool {
        guard let root = repoRoot else { return false }
        let (_, exitCode) = runGit(["commit", "-m", message], at: root)
        if exitCode == 0 {
            statusEntries = loadStatus(at: root)
            recentCommits = loadLog(at: root)
            loadRemoteStatus(at: root)
            return true
        }
        return false
    }

    func push() {
        guard let root = repoRoot else { return }
        isPushing = true
        let (_, exitCode) = runGit(["push"], at: root)
        isPushing = false
        if exitCode == 0 {
            loadRemoteStatus(at: root)
        }
    }

    // MARK: - Read Operations (git CLI)

    private func findRepoRoot(for directory: URL) -> URL? {
        let (output, exitCode) = runGit(["rev-parse", "--show-toplevel"], at: directory)
        guard exitCode == 0, !output.isEmpty else { return nil }
        return URL(fileURLWithPath: output)
    }

    private func loadBranch(at root: URL) -> String {
        let (output, exitCode) = runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: root)
        guard exitCode == 0 else { return "HEAD" }
        return output.isEmpty ? "HEAD" : output
    }

    private func loadRemoteStatus(at root: URL) {
        // Check if a remote tracking branch exists
        let (upstream, upstreamExit) = runGit(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            at: root
        )
        hasRemote = upstreamExit == 0 && !upstream.isEmpty

        if hasRemote {
            let (ahead, _) = runGit(["rev-list", "--count", "@{u}..HEAD"], at: root)
            aheadCount = Int(ahead) ?? 0
            let (behind, _) = runGit(["rev-list", "--count", "HEAD..@{u}"], at: root)
            behindCount = Int(behind) ?? 0
        } else {
            aheadCount = 0
            behindCount = 0
        }
    }

    private func loadStatus(at root: URL) -> [GitStatusEntry] {
        let (output, exitCode) = runGit(["status", "--porcelain=v1"], at: root)
        guard exitCode == 0 else { return [] }

        var entries: [GitStatusEntry] = []
        for line in output.components(separatedBy: "\n") where line.count >= 4 {
            let indexStatus = line[line.index(line.startIndex, offsetBy: 0)]
            let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
            let path = String(line[line.index(line.startIndex, offsetBy: 3)...])

            // Staged entry
            if indexStatus != " " && indexStatus != "?" {
                if let status = mapStatus(indexStatus) {
                    entries.append(GitStatusEntry(path: path, status: status, isStaged: true))
                }
            }

            // Unstaged / worktree entry
            if workTreeStatus != " " {
                if indexStatus == "?" {
                    entries.append(GitStatusEntry(path: path, status: .untracked, isStaged: false))
                } else if let status = mapStatus(workTreeStatus) {
                    entries.append(GitStatusEntry(path: path, status: status, isStaged: false))
                }
            }
        }

        return entries
    }

    private func mapStatus(_ char: Character) -> GitFileStatus? {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "U": return .conflicted
        case "?": return .untracked
        default: return nil
        }
    }

    private func loadLog(at root: URL) -> [GitCommitInfo] {
        let format = "%H%n%h%n%s%n%an%n%aI"
        let (output, exitCode) = runGit(["log", "--format=\(format)", "-20"], at: root)
        guard exitCode == 0, !output.isEmpty else { return [] }

        let lines = output.components(separatedBy: "\n")
        var commits: [GitCommitInfo] = []
        var i = 0
        while i + 4 < lines.count {
            let hash = lines[i]
            let shortHash = lines[i + 1]
            let message = lines[i + 2]
            let author = lines[i + 3]
            let dateStr = lines[i + 4]
            i += 5

            let date = ISO8601DateFormatter().date(from: dateStr) ?? .now
            commits.append(GitCommitInfo(
                hash: hash,
                shortHash: shortHash,
                message: message,
                author: author,
                date: date
            ))
        }

        return commits
    }

    // MARK: - Git Process Runner

    @discardableResult
    private func runGit(_ arguments: [String], at directory: URL) -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lastError = error.localizedDescription
            return ("", -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 && !output.isEmpty {
            lastError = output
        }

        return (output, process.terminationStatus)
    }
}
