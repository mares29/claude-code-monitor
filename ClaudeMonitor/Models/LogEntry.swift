import Foundation

struct LogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let sessionId: String?

    init(id: UUID = UUID(), timestamp: Date, level: LogLevel, message: String, sessionId: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.sessionId = sessionId
    }
}
