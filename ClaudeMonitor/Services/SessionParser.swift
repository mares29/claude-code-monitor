import Foundation

struct SessionParser: Sendable {

    /// Parse session JSONL file into conversation turns
    func parse(sessionPath: URL) -> [ConversationTurn] {
        guard let data = try? Data(contentsOf: sessionPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseContent(content)
    }

    /// Parse from offset, return turns and new offset
    func parseIncremental(sessionPath: URL, fromOffset: UInt64) -> (turns: [ConversationTurn], newOffset: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: sessionPath) else {
            return ([], fromOffset)
        }
        defer { try? handle.close() }

        try? handle.seek(toOffset: fromOffset)
        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return ([], fromOffset)
        }

        let turns = parseContent(content)
        let newOffset = fromOffset + UInt64(data.count)
        return (turns, newOffset)
    }

    // MARK: - Private

    private func parseContent(_ content: String) -> [ConversationTurn] {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var entries: [SessionEntry] = []
        let decoder = JSONDecoder()

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(SessionEntry.self, from: data) else {
                continue
            }
            entries.append(entry)
        }

        return buildTurns(from: entries)
    }

    private func buildTurns(from entries: [SessionEntry]) -> [ConversationTurn] {
        var turns: [ConversationTurn] = []
        var toolResults: [String: ToolCallResult] = [:] // toolUseId -> result

        // First pass: collect tool results and extract user prompts
        for entry in entries where entry.type == "user" {
            guard let uuid = entry.uuid,
                  let content = entry.message?.content else { continue }

            var hasToolResult = false
            var userTextParts: [String] = []

            for item in content {
                if item.type == "tool_result" {
                    hasToolResult = true
                    if let toolId = item.toolUseId {
                        let resultContent = item.content?.asString
                        let isError = item.isError ?? false
                        toolResults[toolId] = ToolCallResult(
                            isSuccess: !isError,
                            content: isError ? nil : resultContent,
                            errorMessage: isError ? resultContent : nil
                        )
                    }
                } else if item.type == "text", let text = item.text {
                    userTextParts.append(text)
                }
            }

            // If this entry has user text, show it as a user turn
            if !userTextParts.isEmpty {
                let timestamp = entry.parsedTimestamp ?? Date()
                turns.append(ConversationTurn(
                    id: uuid,
                    timestamp: timestamp,
                    role: .user,
                    text: userTextParts.joined(separator: "\n")
                ))
            }
        }

        // Second pass: build turns from assistant messages
        for entry in entries where entry.type == "assistant" {
            guard let uuid = entry.uuid,
                  let message = entry.message,
                  let content = message.content else { continue }

            let timestamp = entry.parsedTimestamp ?? Date()

            // Extract text
            let textParts = content.compactMap { item -> String? in
                item.type == "text" ? item.text : nil
            }
            let text = textParts.isEmpty ? nil : textParts.joined(separator: "\n")

            // Extract tool calls
            var toolCalls: [ToolCall] = []
            var agentSpawns: [AgentSummary] = []

            for item in content where item.type == "tool_use" {
                guard let name = item.name,
                      let toolId = item.id ?? item.toolUseId else { continue }

                let input = item.input ?? [:]
                let inputJSON = (try? JSONSerialization.data(withJSONObject: input.mapValues { $0.value }))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                let filePath = input["file_path"]?.stringValue ?? input["path"]?.stringValue
                let command = input["command"]?.stringValue
                let pattern = input["pattern"]?.stringValue

                let toolInput = ToolCallInput(
                    filePath: filePath,
                    command: command,
                    pattern: pattern,
                    rawJSON: inputJSON
                )

                // Check for Task tool (agent spawn)
                if name == "Task" {
                    let agentType = input["subagent_type"]?.stringValue ?? "unknown"
                    agentSpawns.append(AgentSummary(
                        id: toolId,
                        type: AgentType(from: agentType),
                        turnCount: 0,
                        status: .running,
                        parentTurnId: uuid
                    ))
                } else {
                    toolCalls.append(ToolCall(
                        id: toolId,
                        name: name,
                        input: toolInput,
                        result: toolResults[toolId],
                        timestamp: timestamp
                    ))
                }
            }

            // Extract token usage
            var tokenUsage: TokenUsage? = nil
            if let usage = message.usage {
                tokenUsage = TokenUsage(
                    inputTokens: usage.inputTokens ?? 0,
                    outputTokens: usage.outputTokens ?? 0,
                    cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                    cacheCreationTokens: usage.cacheCreationInputTokens ?? 0
                )
            }

            // Extract model
            let model = message.model

            // Only include turns with actual content
            let hasContent = text != nil || !toolCalls.isEmpty || !agentSpawns.isEmpty
            if hasContent {
                turns.append(ConversationTurn(
                    id: uuid,
                    timestamp: timestamp,
                    role: .assistant,
                    text: text,
                    toolCalls: toolCalls,
                    tokenUsage: tokenUsage,
                    agentSpawns: agentSpawns,
                    model: model
                ))
            }
        }

        // Sort newest first
        return turns.sorted { $0.timestamp > $1.timestamp }
    }
}
