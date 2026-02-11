import SwiftUI

@Observable @MainActor
final class MonitorState {
    var instances: [ClaudeInstance] = []
    var logEntries: [LogEntry] = []
    var selectedItem: TreeSelection? = nil
    var consoleFilter: LogLevel? = nil
    var consoleSearchText: String = ""
    var isAutoScrollEnabled: Bool = true
    var isMainWindowVisible: Bool = false

    // Activity & Conflicts (techniques 1-5)
    var recentOperations: [ToolOperation] = []
    var activeConflicts: [FileConflict] = []
    var sessionSparklines: [String: String] = [:]

    // Per-session live data (keyed by sessionId)
    var sessionCurrentActions: [String: String] = [:]
    var sessionLatestTokens: [String: TokenUsage] = [:]
    var sessionCurrentModels: [String: String] = [:]

    // Git diff data (keyed by working directory)
    var gitDiffs: [String: GitDiffSummary] = [:]

    private let maxLogEntries = 10_000
    private let maxRecentOps = 100

    var groupedInstances: [InstanceGroup] {
        Dictionary(grouping: instances) { $0.workingDirectory }
            .map { InstanceGroup(workingDirectory: $0.key, instances: $0.value) }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var filteredLogs: [LogEntry] {
        logEntries.filter { entry in
            (consoleFilter == nil || entry.level == consoleFilter) &&
            (consoleSearchText.isEmpty ||
             entry.message.localizedStandardContains(consoleSearchText))
        }
    }

    var menuBarStatus: MenuBarStatus {
        guard !instances.isEmpty else { return .idle }
        let sixtySecondsAgo = Date().addingTimeInterval(-60)
        let hasRecentError = logEntries.contains {
            $0.level == .error && $0.timestamp > sixtySecondsAgo
        }
        return hasRecentError ? .warning : .active
    }

    func addLogEntry(_ entry: LogEntry) {
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    func updateInstances(_ newInstances: [ClaudeInstance]) {
        // Preserve startTime from existing instances
        let existingStartTimes = Dictionary(uniqueKeysWithValues: instances.map { ($0.pid, $0.startTime) })

        // Sort instances by display name (last path component) for stable ordering
        instances = newInstances.map { instance in
            if let existingStartTime = existingStartTimes[instance.pid] {
                return ClaudeInstance(
                    pid: instance.pid,
                    workingDirectory: instance.workingDirectory,
                    sessionId: instance.sessionId,
                    startTime: existingStartTime,
                    arguments: instance.arguments,
                    agents: instance.agents,
                    isActive: instance.isActive,
                    terminalApp: instance.terminalApp,
                    cpuPercent: instance.cpuPercent,
                    memoryMB: instance.memoryMB,
                    tty: instance.tty
                )
            }
            return instance
        }.sorted { a, b in
            let nameA = URL(fileURLWithPath: a.workingDirectory).lastPathComponent.lowercased()
            let nameB = URL(fileURLWithPath: b.workingDirectory).lastPathComponent.lowercased()
            if nameA != nameB {
                return nameA < nameB
            }
            // Secondary sort by PID for stable ordering when names match
            return a.pid < b.pid
        }

        // Clear selection if selected instance disappeared
        if case .instance(let pid) = selectedItem,
           !instances.contains(where: { $0.pid == pid }) {
            selectedItem = nil
        }
    }

    // MARK: - Activity Tracking

    func addOperations(_ ops: [ToolOperation]) {
        recentOperations.append(contentsOf: ops)
        if recentOperations.count > maxRecentOps {
            recentOperations.removeFirst(recentOperations.count - maxRecentOps)
        }
    }

    func updateConflicts(_ conflicts: [FileConflict]) {
        activeConflicts = conflicts
    }

    func updateSparkline(sessionId: String, sparkline: String) {
        sessionSparklines[sessionId] = sparkline
    }

    func updateSessionLiveData(sessionId: String, action: String?, model: String?, tokens: TokenUsage?) {
        if let action { sessionCurrentActions[sessionId] = action }
        if let model { sessionCurrentModels[sessionId] = model }
        if let tokens { sessionLatestTokens[sessionId] = tokens }
    }

    func updateGitDiffs(_ diffs: [String: GitDiffSummary]) {
        gitDiffs = diffs
    }

    var hasActiveConflicts: Bool {
        !activeConflicts.isEmpty
    }

    var criticalConflictCount: Int {
        activeConflicts.filter { $0.severity == .critical }.count
    }
}
