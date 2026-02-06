import Foundation

actor ConflictDetector {
    /// Recent operations keyed by file path
    private var recentOps: [String: [ToolOperation]] = [:]

    /// Active conflicts
    private(set) var activeConflicts: [FileConflict] = []

    private let conflictWindow: TimeInterval = 5.0
    private let conflictExpiry: TimeInterval = 10.0

    /// Record an operation and check for conflicts
    @discardableResult
    func record(_ op: ToolOperation) -> FileConflict? {
        guard let path = op.filePath else { return nil }

        // Clean old operations outside window
        let cutoff = Date().addingTimeInterval(-conflictWindow)
        recentOps[path] = (recentOps[path] ?? []).filter { $0.timestamp > cutoff }

        // Add new op
        recentOps[path, default: []].append(op)

        // Check for conflict
        let ops = recentOps[path] ?? []
        guard ops.count >= 2 else { return nil }

        // Get unique sources (sessionId + agentId)
        let sources = Set(ops.map { "\($0.sessionId):\($0.agentId ?? "main")" })
        guard sources.count >= 2 else { return nil }

        // Determine severity
        let writeCount = ops.filter { $0.isWrite }.count
        let severity: ConflictSeverity = writeCount >= 2 ? .critical : .warning

        let conflict = FileConflict(
            filePath: path,
            operations: ops,
            severity: severity
        )

        // Add if not duplicate
        if !activeConflicts.contains(where: { $0.filePath == path }) {
            activeConflicts.append(conflict)
        } else {
            // Update existing conflict with new operations
            if let idx = activeConflicts.firstIndex(where: { $0.filePath == path }) {
                activeConflicts[idx] = conflict
            }
        }

        return conflict
    }

    /// Clean expired conflicts
    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-conflictExpiry)
        activeConflicts.removeAll { $0.detectedAt < cutoff }

        // Also clean old operations
        let opCutoff = Date().addingTimeInterval(-conflictWindow)
        for (path, ops) in recentOps {
            recentOps[path] = ops.filter { $0.timestamp > opCutoff }
            if recentOps[path]?.isEmpty == true {
                recentOps.removeValue(forKey: path)
            }
        }
    }

    /// Get current conflict count by severity
    var conflictSummary: (warnings: Int, critical: Int) {
        let w = activeConflicts.filter { $0.severity == .warning }.count
        let c = activeConflicts.filter { $0.severity == .critical }.count
        return (w, c)
    }

    /// Clear all conflicts
    func clearAll() {
        activeConflicts.removeAll()
        recentOps.removeAll()
    }
}
