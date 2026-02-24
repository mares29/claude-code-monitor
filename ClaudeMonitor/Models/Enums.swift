import SwiftUI

enum AgentType: Codable, Sendable, Hashable {
    case explore
    case plan
    case bash
    case general
    case codeReview
    case codeSimplifier
    case compact
    case promptSuggestion
    case custom(String)

    init(from string: String) {
        // Strip skill prefix (e.g., "code-simplifier:code-simplifier" → "code-simplifier")
        let normalized = string.components(separatedBy: ":").first?.lowercased() ?? string.lowercased()
        switch normalized {
        case "explore": self = .explore
        case "plan": self = .plan
        case "bash": self = .bash
        case "general", "general-purpose": self = .general
        case "codereview", "code_review", "code-review", "code-reviewer": self = .codeReview
        case "code-simplifier", "codesimplifier", "code_simplifier": self = .codeSimplifier
        case "compact": self = .compact
        case "prompt_suggestion", "promptsuggestion": self = .promptSuggestion
        default: self = .custom(string)
        }
    }

    var displayName: String {
        switch self {
        case .explore: "Explore"
        case .plan: "Plan"
        case .bash: "Bash"
        case .general: "General"
        case .codeReview: "Code Review"
        case .codeSimplifier: "Code Simplifier"
        case .compact: "Compact"
        case .promptSuggestion: "Prompt Suggestion"
        case .custom(let raw): raw
        }
    }
}

/// Instance activity state derived from JSONL file signals
enum ActivityState: Sendable, Equatable {
    /// Actively generating (JSONL modified recently + last entry is assistant mid-turn)
    case working
    /// Waiting for user input (last entry is assistant with end_turn)
    case waiting
    /// No recent JSONL activity
    case idle

    var isActive: Bool { self == .working }

    var label: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting"
        case .idle: "Idle"
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
        case .active: Color.accentColor
        case .warning: .yellow
        }
    }
}
