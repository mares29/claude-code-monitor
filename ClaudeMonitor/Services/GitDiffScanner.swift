import Foundation

actor GitDiffScanner {
    func scan(workingDirectories: [String]) async -> [String: GitDiffSummary] {
        var results: [String: GitDiffSummary] = [:]
        for dir in workingDirectories {
            results[dir] = await scanDirectory(dir)
        }
        return results
    }

    private func scanDirectory(_ directory: String) async -> GitDiffSummary {
        async let unstaged = runGitDiff(in: directory, cached: false)
        async let staged = runGitDiff(in: directory, cached: true)

        let entries = await unstaged + staged
        return GitDiffSummary(entries: entries, timestamp: Date())
    }

    private func runGitDiff(in directory: String, cached: Bool) async -> [GitDiffEntry] {
        var numstatArgs = ["diff", "--numstat"]
        if cached { numstatArgs.append("--cached") }

        guard let numstatOutput = await runGit(args: numstatArgs, in: directory) else { return [] }

        var statusArgs = ["diff", "--name-status"]
        if cached { statusArgs.append("--cached") }

        let statusOutput = await runGit(args: statusArgs, in: directory)
        let statusMap = parseNameStatus(statusOutput ?? "")

        return parseNumstat(numstatOutput, isStaged: cached, statusMap: statusMap)
    }

    private func parseNumstat(_ output: String, isStaged: Bool, statusMap: [String: GitDiffEntry.FileStatus]) -> [GitDiffEntry] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { return nil }
            let ins = Int(parts[0]) ?? 0
            let del = Int(parts[1]) ?? 0
            let path = String(parts[2])
            let status = statusMap[path] ?? .modified
            return GitDiffEntry(filePath: path, insertions: ins, deletions: del, isStaged: isStaged, status: status)
        }
    }

    private func parseNameStatus(_ output: String) -> [String: GitDiffEntry.FileStatus] {
        var map: [String: GitDiffEntry.FileStatus] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let statusChar = String(parts[0].prefix(1))
            let path = String(parts[1])
            map[path] = GitDiffEntry.FileStatus(rawValue: statusChar) ?? .modified
        }
        return map
    }

    func fullDiff(for filePath: String, in directory: String) async -> String {
        let unstaged = await runGit(args: ["diff", "--", filePath], in: directory) ?? ""
        let staged = await runGit(args: ["diff", "--cached", "--", filePath], in: directory) ?? ""

        if !unstaged.isEmpty && !staged.isEmpty {
            return "── Staged ──\n\(staged)\n── Unstaged ──\n\(unstaged)"
        }
        return unstaged.isEmpty ? staged : unstaged
    }

    private func runGit(args: [String], in directory: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
