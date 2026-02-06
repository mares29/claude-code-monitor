import Foundation

struct ToolOperationParser: Sendable {

    /// Parse a single JSONL line for tool operations
    nonisolated func parse(line: String, sessionId: String) -> [ToolOperation] {
        guard let data = line.data(using: .utf8),
              let entry = try? JSONDecoder().decode(ToolUseEntry.self, from: data),
              let content = entry.message?.content else { return [] }

        let timestamp = entry.timestamp ?? Date()
        var ops: [ToolOperation] = []

        for item in content where item.type == "tool_use" {
            guard let toolName = item.name?.lowercased(),
                  let toolType = ToolType(rawValue: toolName) else { continue }

            let filePath = item.input?.filePath ?? item.input?.path ?? item.input?.notebookPath
            let isWrite = toolType.isWriteOperation

            ops.append(ToolOperation(
                timestamp: timestamp,
                sessionId: sessionId,
                agentId: entry.agentId,
                tool: toolType,
                filePath: filePath,
                isWrite: isWrite
            ))
        }

        return ops
    }
}

// MARK: - Decoding models

private struct ToolUseEntry: Decodable {
    let message: ToolUseMessage?
    let timestamp: Date?
    let agentId: String?

    enum CodingKeys: String, CodingKey {
        case message, timestamp, agentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decodeIfPresent(ToolUseMessage.self, forKey: .message)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)

        if let ts = try? c.decode(String.self, forKey: .timestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = fmt.date(from: ts)
        } else {
            timestamp = nil
        }
    }
}

private struct ToolUseMessage: Decodable {
    let content: [ToolUseContent]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try? c.decode([ToolUseContent].self, forKey: .content)
    }

    enum CodingKeys: String, CodingKey { case content }
}

private struct ToolUseContent: Decodable {
    let type: String?
    let name: String?
    let input: ToolInput?
}

private struct ToolInput: Decodable {
    let filePath: String?
    let path: String?
    let notebookPath: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case path
        case notebookPath = "notebook_path"
    }
}
