import Foundation

struct LogParser: Sendable {
    // Pattern: 2026-01-29T21:16:26.939Z [DEBUG] message...
    private static let pattern = #"^(\d{4}-\d{2}-\d{2}T[\d:.]+Z)\s+\[(DEBUG|INFO|ERROR)\]\s+(.*)$"#
    private static let regex = try! NSRegularExpression(pattern: pattern)
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func parse(line: String, sessionId: String? = nil) -> LogEntry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else {
            return nil
        }

        guard let timestampRange = Range(match.range(at: 1), in: line),
              let levelRange = Range(match.range(at: 2), in: line),
              let messageRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let timestampStr = String(line[timestampRange])
        let levelStr = String(line[levelRange])
        let message = String(line[messageRange])

        guard let timestamp = dateFormatter.date(from: timestampStr),
              let level = LogLevel(rawValue: levelStr) else {
            return nil
        }

        return LogEntry(
            timestamp: timestamp,
            level: level,
            message: message,
            sessionId: sessionId
        )
    }
}
