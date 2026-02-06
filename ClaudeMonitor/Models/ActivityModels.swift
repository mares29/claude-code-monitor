import Foundation

/// Tracks file read position for incremental tailing
struct FilePosition: Sendable {
    let path: String
    var offset: UInt64
    var lastModified: Date
}

/// A tool operation parsed from session JSONL
struct ToolOperation: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sessionId: String
    let agentId: String?
    let tool: ToolType
    let filePath: String?
    let isWrite: Bool

    init(id: UUID = UUID(), timestamp: Date, sessionId: String, agentId: String?, tool: ToolType, filePath: String?, isWrite: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.agentId = agentId
        self.tool = tool
        self.filePath = filePath
        self.isWrite = isWrite
    }
}

enum ToolType: String, Sendable, CaseIterable {
    case read
    case write
    case edit
    case bash
    case grep
    case glob
    case search
    case task

    var icon: String {
        switch self {
        case .read: "doc.text"
        case .write: "doc.badge.plus"
        case .edit: "pencil"
        case .bash: "terminal"
        case .grep: "magnifyingglass"
        case .glob: "folder"
        case .search: "magnifyingglass"
        case .task: "gearshape.2"
        }
    }

    var label: String {
        switch self {
        case .read: "Read"
        case .write: "Write"
        case .edit: "Edit"
        case .bash: "Bash"
        case .grep: "Grep"
        case .glob: "Glob"
        case .search: "Search"
        case .task: "Agent"
        }
    }

    var isWriteOperation: Bool {
        self == .write || self == .edit
    }
}

/// Conflict when multiple agents touch same file
struct FileConflict: Identifiable, Sendable {
    let id: UUID
    let filePath: String
    let operations: [ToolOperation]
    let severity: ConflictSeverity
    let detectedAt: Date

    init(id: UUID = UUID(), filePath: String, operations: [ToolOperation], severity: ConflictSeverity, detectedAt: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.operations = operations
        self.severity = severity
        self.detectedAt = detectedAt
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

enum ConflictSeverity: String, Sendable {
    case warning
    case critical

    var displayName: String {
        rawValue.capitalized
    }
}

/// Session index entry from sessions-index.json
struct SessionIndexEntry: Decodable, Sendable {
    let sessionId: String
    let projectPath: String
    let modified: String
}

struct SessionsIndexFile: Decodable, Sendable {
    let version: Int
    let entries: [SessionIndexEntry]
}
