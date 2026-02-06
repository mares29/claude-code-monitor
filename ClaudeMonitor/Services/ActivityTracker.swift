import Foundation

actor ActivityTracker {
    /// Activity counts per second, keyed by sessionId
    private var activityBuckets: [String: [Date: Int]] = [:]

    private let historyWindow: TimeInterval = 20.0

    /// Record activity for a session
    func record(sessionId: String, count: Int = 1) {
        let bucket = Date().truncatedToSecond
        activityBuckets[sessionId, default: [:]][bucket, default: 0] += count
        prune(sessionId: sessionId)
    }

    /// Get sparkline data (last 20 values, one per second)
    func sparklineData(for sessionId: String) -> [Int] {
        let now = Date().truncatedToSecond
        let buckets = activityBuckets[sessionId] ?? [:]

        return (0..<20).reversed().map { secondsAgo in
            let t = now.addingTimeInterval(-Double(secondsAgo))
            return buckets[t] ?? 0
        }
    }

    /// Render sparkline as unicode string
    func sparkline(for sessionId: String) -> String {
        let data = sparklineData(for: sessionId)
        guard let maxVal = data.max(), maxVal > 0 else {
            return String(repeating: "▁", count: 20)
        }

        let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        return data.map { val in
            let idx = val == 0 ? 0 : min(7, (val * 7) / maxVal)
            return bars[idx]
        }.joined()
    }

    /// Get total activity in last N seconds
    func recentActivityCount(for sessionId: String, seconds: Int = 5) -> Int {
        let now = Date().truncatedToSecond
        let buckets = activityBuckets[sessionId] ?? [:]

        return (0..<seconds).reduce(0) { sum, secondsAgo in
            let t = now.addingTimeInterval(-Double(secondsAgo))
            return sum + (buckets[t] ?? 0)
        }
    }

    private func prune(sessionId: String) {
        let cutoff = Date().addingTimeInterval(-historyWindow)
        activityBuckets[sessionId]?.keys
            .filter { $0 < cutoff }
            .forEach { activityBuckets[sessionId]?.removeValue(forKey: $0) }
    }

    /// Clear all activity data
    func clearAll() {
        activityBuckets.removeAll()
    }
}

// MARK: - Date extension

extension Date {
    nonisolated var truncatedToSecond: Date {
        Date(timeIntervalSince1970: floor(timeIntervalSince1970))
    }
}
