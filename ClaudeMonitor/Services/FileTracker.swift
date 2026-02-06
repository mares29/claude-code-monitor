import Foundation

actor FileTracker {
    /// File positions keyed by path
    private var positions: [String: FilePosition] = [:]

    /// Cached session index per project (keyed by encoded project path)
    private var sessionIndexCache: [String: (entries: [SessionIndexEntry], loadedAt: Date)] = [:]

    private let cacheExpiry: TimeInterval = 5.0

    /// Read only NEW lines from a JSONL file since last read
    func readNewLines(from path: String) -> [String] {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? UInt64,
              let modDate = attrs[.modificationDate] as? Date else { return [] }

        let pos = positions[path]

        // Skip if unmodified
        if let p = pos, p.lastModified == modDate { return [] }

        // Handle file truncation (new session started)
        let startOffset: UInt64
        if let p = pos, p.offset > fileSize {
            startOffset = 0
        } else {
            startOffset = pos?.offset ?? 0
        }

        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            return []
        }

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else { return [] }

        // Update position
        positions[path] = FilePosition(path: path, offset: fileSize, lastModified: modDate)

        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Get cached session index, refresh if stale
    func getSessionIndex(for encodedProjectPath: String) -> [SessionIndexEntry]? {
        if let cached = sessionIndexCache[encodedProjectPath],
           Date().timeIntervalSince(cached.loadedAt) < cacheExpiry {
            return cached.entries
        }

        let indexPath = "\(NSHomeDirectory())/.claude/projects/\(encodedProjectPath)/sessions-index.json"
        guard let data = FileManager.default.contents(atPath: indexPath),
              let index = try? JSONDecoder().decode(SessionsIndexFile.self, from: data) else {
            return nil
        }

        sessionIndexCache[encodedProjectPath] = (index.entries, Date())
        return index.entries
    }

    /// Reset position for a file (e.g., if file was truncated)
    func resetPosition(for path: String) {
        positions.removeValue(forKey: path)
    }

    /// Clear all cached data
    func clearCache() {
        positions.removeAll()
        sessionIndexCache.removeAll()
    }
}
