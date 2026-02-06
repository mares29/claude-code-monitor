import SwiftUI

enum AgentType: String, CaseIterable, Codable, Sendable {
    case explore
    case plan
    case bash
    case general
    case codeReview
    case compact
    case promptSuggestion
    case unknown

    init(from string: String) {
        switch string.lowercased() {
        case "explore": self = .explore
        case "plan": self = .plan
        case "bash": self = .bash
        case "general", "general-purpose": self = .general
        case "codereview", "code_review", "code-review": self = .codeReview
        case "compact": self = .compact
        case "prompt_suggestion", "promptsuggestion": self = .promptSuggestion
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .explore: "Explore"
        case .plan: "Plan"
        case .bash: "Bash"
        case .general: "General"
        case .codeReview: "Code Review"
        case .compact: "Compact"
        case .promptSuggestion: "Prompt Suggestion"
        case .unknown: "Unknown"
        }
    }
}

enum AgentStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

enum LogLevel: String, CaseIterable, Codable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .error: .red
        }
    }
}

enum MenuBarStatus: Sendable {
    case idle
    case active
    case warning

    var iconName: String {
        switch self {
        case .idle: "circle"
        case .active: "circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .gray
        case .active: .blue
        case .warning: .yellow
        }
    }
}
