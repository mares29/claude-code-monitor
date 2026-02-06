import Foundation

struct ClaudeInstance: Identifiable, Hashable, Sendable {
    var id: Int { pid }
    let pid: Int
    let workingDirectory: String
    let sessionId: String?
    let startTime: Date
    let arguments: [String]
    var agents: [Agent]
    var isActive: Bool

    // Process metadata
    let terminalApp: String?   // "Warp", "iTerm", "Terminal", etc.
    let cpuPercent: Double     // 0.0-100.0
    let memoryMB: Int          // RSS in MB
    let tty: String?           // "ttys000", etc.

    // MARK: - Flag Detection

    /// All CLI flags passed to this instance (excluding the executable and positional args)
    var flags: [String] {
        arguments.filter { $0.hasPrefix("-") }
    }

    /// Whether instance is running with --dangerously-skip-permissions
    var isDangerousMode: Bool {
        arguments.contains("--dangerously-skip-permissions")
    }

    /// Check if a specific flag is present
    func hasFlag(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    /// Human-readable flag names for display
    var displayFlags: [String] {
        flags.compactMap { flag in
            switch flag {
            case "--dangerously-skip-permissions": return nil  // Shown separately as warning
            case "-c", "--continue": return "continue"
            case "-r", "--resume": return "resume"
            case "-p", "--print": return "print"
            case "--verbose": return "verbose"
            case "--no-cache": return "no-cache"
            case "--allowedTools": return "tools-restricted"
            case "--disallowedTools": return "tools-blocked"
            case "--model": return "custom-model"
            case "--max-tokens": return "max-tokens"
            case "--max-turns": return "max-turns"
            default:
                // Strip leading dashes and return as-is for unknown flags
                let cleaned = flag.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                return cleaned.isEmpty ? nil : cleaned
            }
        }
    }

    init(
        pid: Int,
        workingDirectory: String,
        sessionId: String? = nil,
        startTime: Date = Date(),
        arguments: [String] = [],
        agents: [Agent] = [],
        isActive: Bool = true,
        terminalApp: String? = nil,
        cpuPercent: Double = 0.0,
        memoryMB: Int = 0,
        tty: String? = nil
    ) {
        self.pid = pid
        self.workingDirectory = workingDirectory
        self.sessionId = sessionId
        self.startTime = startTime
        self.arguments = arguments
        self.agents = agents
        self.isActive = isActive
        self.terminalApp = terminalApp
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.tty = tty
    }

    /// Extract session ID from arguments (--resume <uuid>), active debug log, or sessions-index.json
    static func extractSessionId(from arguments: [String], workingDirectory: String? = nil, pid: Int? = nil) -> String? {
        // First try --resume argument
        if let resumeIndex = arguments.firstIndex(of: "--resume"),
           resumeIndex + 1 < arguments.count {
            let sessionId = arguments[resumeIndex + 1]
            if UUID(uuidString: sessionId) != nil {
                return sessionId
            }
        }

        // Try to find session from process's open debug log file
        if let pid = pid, let sessionId = findActiveSessionFromDebugLog(pid: pid, workingDirectory: workingDirectory) {
            return sessionId
        }

        // Fall back to reading from sessions-index.json
        guard let workingDir = workingDirectory else { return nil }
        return readSessionIdFromIndex(for: workingDir)
    }

    /// Find the active session ID by checking recently modified debug log files
    private static func findActiveSessionFromDebugLog(pid: Int, workingDirectory: String?) -> String? {
        guard let workingDir = workingDirectory else { return nil }

        let fm = FileManager.default
        let debugDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/debug")

        // Get all debug log files sorted by modification time (most recent first)
        guard let files = try? fm.contentsOfDirectory(
            at: debugDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        // Filter to .txt files and sort by modification date
        let sortedFiles = files
            .filter { $0.pathExtension == "txt" }
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = attrs.contentModificationDate else { return nil }
                return (url, modDate)
            }
            .sorted { $0.1 > $1.1 } // Most recent first

        // Find the first debug log that belongs to this project and was modified recently
        let twoMinutesAgo = Date().addingTimeInterval(-120)

        for (url, modDate) in sortedFiles {
            // Only consider recently modified files (active sessions)
            guard modDate > twoMinutesAgo else { continue }

            let sessionId = url.deletingPathExtension().lastPathComponent

            // Check if this session belongs to the project
            if sessionBelongsToProject(sessionId: sessionId, workingDirectory: workingDir) {
                return sessionId
            }
        }

        return nil
    }

    /// Check if a session ID belongs to a specific project
    private static func sessionBelongsToProject(sessionId: String, workingDirectory: String) -> Bool {
        let projectsPath = projectsPath(for: workingDirectory)
        let fm = FileManager.default

        // First check: does the session JSONL file exist in this project?
        let sessionFilePath = "\(projectsPath)/\(sessionId).jsonl"
        if fm.fileExists(atPath: sessionFilePath) {
            return true
        }

        // Second check: does the session directory exist?
        let sessionDirPath = "\(projectsPath)/\(sessionId)"
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sessionDirPath, isDirectory: &isDir), isDir.boolValue {
            return true
        }

        // Fallback: check sessions-index.json
        let indexPath = "\(projectsPath)/sessions-index.json"
        if let data = fm.contents(atPath: indexPath),
           let index = try? JSONDecoder().decode(SessionsIndexFile.self, from: data) {
            return index.entries.contains { $0.sessionId == sessionId }
        }
        return false
    }

    /// Read session ID from sessions-index.json for a given working directory
    private static func readSessionIdFromIndex(for workingDirectory: String) -> String? {
        // Try the working directory and walk up to find a sessions-index.json
        var currentPath = workingDirectory
        let fm = FileManager.default

        while currentPath != "/" && !currentPath.isEmpty {
            let projectsPath = projectsPath(for: currentPath)
            let indexPath = "\(projectsPath)/sessions-index.json"

            if let data = fm.contents(atPath: indexPath),
               let index = try? JSONDecoder().decode(SessionsIndexFile.self, from: data) {
                // Find sessions matching the original working directory (or starting with it)
                let matchingSessions = index.entries.filter {
                    $0.projectPath == workingDirectory || workingDirectory.hasPrefix($0.projectPath + "/")
                }

                if let session = matchingSessions.sorted(by: { $0.modified > $1.modified }).first {
                    return session.sessionId
                }
            }

            // Move up one directory
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }

        return nil
    }

    /// Convert working directory to Claude projects path
    static func projectsPath(for workingDirectory: String) -> String {
        // Claude encodes paths by replacing / and . with -
        let encoded = workingDirectory
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "\(NSHomeDirectory())/.claude/projects/\(encoded)"
    }
}

