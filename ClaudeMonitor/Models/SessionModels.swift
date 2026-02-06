import Foundation

// MARK: - Core Types

enum TurnRole: String, Sendable {
    case user
    case assistant
}

struct ConversationTurn: Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let role: TurnRole
    let text: String?
    let toolCalls: [ToolCall]
    let tokenUsage: TokenUsage?
    let agentSpawns: [AgentSummary]
    let model: String?

    init(
        id: String,
        timestamp: Date,
        role: TurnRole = .assistant,
        text: String? = nil,
        toolCalls: [ToolCall] = [],
        tokenUsage: TokenUsage? = nil,
        agentSpawns: [AgentSummary] = [],
        model: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.tokenUsage = tokenUsage
        self.agentSpawns = agentSpawns
        self.model = model
    }

    /// Short display name for model
    /// Parses "claude-opus-4-6-20251101" -> "OPUS 4.6"
    var displayModel: String? {
        guard let model = model, model != "<synthetic>" else { return nil }
        let families = ["opus", "sonnet", "haiku"]
        for family in families {
            guard model.contains(family) else { continue }
            let label = family.uppercased()
            // Extract version: digits after family name in "claude-opus-4-5..."
            let parts = model.components(separatedBy: "-")
            if let idx = parts.firstIndex(of: family),
               idx + 2 < parts.count,
               let major = Int(parts[idx + 1]),
               let minor = Int(parts[idx + 2]) {
                return "\(label) \(major).\(minor)"
            }
            return label
        }
        return model
    }
}

struct ToolCall: Identifiable, Sendable {
    let id: String
    let name: String
    let input: ToolCallInput
    let result: ToolCallResult?
    let timestamp: Date
}

struct ToolCallInput: Sendable {
    let filePath: String?
    let command: String?
    let pattern: String?
    let rawJSON: String  // Full input for expandable view
}

struct ToolCallResult: Sendable {
    let isSuccess: Bool
    let content: String?
    let errorMessage: String?
}

struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int

    var totalInput: Int { inputTokens + cacheReadTokens + cacheCreationTokens }

    var formattedBadge: String {
        let inK = String(format: "%.1fk", Double(totalInput) / 1000)
        let outK = String(format: "%.1fk", Double(outputTokens) / 1000)
        let cachedK = String(format: "%.1fk", Double(cacheReadTokens) / 1000)
        return "↓\(inK) ↑\(outK) ⚡\(cachedK)"
    }
}

struct AgentSummary: Identifiable, Sendable {
    let id: String
    let type: AgentType
    var turnCount: Int
    var status: AgentStatus
    let parentTurnId: String
}

// MARK: - JSONL Decoding Models

struct SessionEntry: Decodable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let timestamp: String?
    let message: SessionMessage?
    let isSidechain: Bool?
    let toolUseID: String?

    var parsedTimestamp: Date? {
        guard let ts = timestamp else { return nil }
        // Create formatter per-call for thread safety (ISO8601DateFormatter is not thread-safe)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: ts)
    }
}

struct SessionMessage: Decodable {
    let role: String?
    let content: [SessionContent]?
    let usage: SessionUsage?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case role, content, usage, model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        usage = try container.decodeIfPresent(SessionUsage.self, forKey: .usage)
        model = try container.decodeIfPresent(String.self, forKey: .model)

        // Handle content being either a string or an array
        if let contentArray = try? container.decodeIfPresent([SessionContent].self, forKey: .content) {
            content = contentArray
        } else if let contentString = try? container.decodeIfPresent(String.self, forKey: .content) {
            // Wrap plain string in a SessionContent with type "text"
            content = [SessionContent(type: "text", text: contentString)]
        } else {
            content = nil
        }
    }
}

struct SessionContent: Decodable {
    let type: String
    let id: String?           // tool_use entries have "id" field
    let text: String?
    let name: String?
    let input: [String: AnyCodable]?
    let toolUseId: String?    // tool_result entries have "tool_use_id" field
    let content: AnyCodableValue?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type, id, text, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    /// Convenience initializer for wrapping plain text
    init(type: String, text: String?) {
        self.type = type
        self.id = nil
        self.text = text
        self.name = nil
        self.input = nil
        self.toolUseId = nil
        self.content = nil
        self.isError = nil
    }
}

struct SessionUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

// MARK: - AnyCodable helpers for dynamic JSON

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    var stringValue: String? { value as? String }
}

enum AnyCodableValue: Decodable {
    case string(String)
    case array([AnyCodableValue])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else {
            self = .other
        }
    }

    var asString: String? {
        switch self {
        case .string(let s): return s
        case .array(let arr): return arr.compactMap(\.asString).joined(separator: "\n")
        case .other: return nil
        }
    }
}
