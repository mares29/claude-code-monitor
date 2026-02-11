import Foundation

struct GitDiffEntry: Identifiable, Hashable, Sendable {
    let filePath: String
    let insertions: Int
    let deletions: Int
    let isStaged: Bool
    let status: FileStatus

    var id: String { "\(isStaged ? "staged" : "unstaged"):\(filePath)" }

    enum FileStatus: String, Sendable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case unknown = "?"
    }
}

struct GitDiffSummary: Sendable {
    let entries: [GitDiffEntry]
    let timestamp: Date

    static let empty = GitDiffSummary(entries: [], timestamp: .distantPast)

    var totalInsertions: Int { entries.reduce(0) { $0 + $1.insertions } }
    var totalDeletions: Int { entries.reduce(0) { $0 + $1.deletions } }
    var fileCount: Int { Set(entries.map(\.filePath)).count }
    var isEmpty: Bool { entries.isEmpty }
}
