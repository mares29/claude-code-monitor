import Foundation

actor AgentScanner {
    private let projectsDirectory: URL

    init() {
        self.projectsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
    }

    /// Scan for agents belonging to a specific session
    func scanAgents(for sessionId: String, projectPath: String) -> [Agent] {
        var agents: [Agent] = []
        let fm = FileManager.default

        // Build path to the project's session directory
        let encodedPath = projectPath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let projectDir = projectsDirectory.appendingPathComponent(encodedPath)

        // Check two locations for agent files:
        // 1. {project}/{sessionId}/subagents/agent-*.jsonl
        // 2. {project}/agent-*.jsonl (root level agents)

        let subagentsDir = projectDir
            .appendingPathComponent(sessionId)
            .appendingPathComponent("subagents")

        // Scan session-specific subagents
        if let sessionAgentFiles = try? fm.contentsOfDirectory(
            at: subagentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            for file in sessionAgentFiles where file.lastPathComponent.hasPrefix("agent-") {
                if let agent = parseAgentFile(file, parentSessionId: sessionId) {
                    agents.append(agent)
                }
            }
        }

        // Also scan root-level agents that belong to this session
        if let rootFiles = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            for file in rootFiles where file.lastPathComponent.hasPrefix("agent-") && file.pathExtension == "jsonl" {
                if let agent = parseAgentFile(file, parentSessionId: sessionId) {
                    // Only include if it belongs to this session
                    if agent.parentSessionId == sessionId {
                        agents.append(agent)
                    }
                }
            }
        }

        return agents
    }

    private func parseAgentFile(_ url: URL, parentSessionId: String) -> Agent? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        // Read first few KB to get the initial messages
        let data = handle.readData(ofLength: 8192)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Parse first line for agentId and sessionId
        guard let firstLine = lines.first,
              let firstEntry = try? JSONDecoder().decode(AgentEntry.self, from: Data(firstLine.utf8)) else {
            return nil
        }

        let agentId = firstEntry.agentId ?? extractAgentId(from: url.lastPathComponent)
        let actualSessionId = firstEntry.sessionId ?? parentSessionId

        // Determine agent type - first try filename, then content
        var agentType = extractAgentType(from: url.lastPathComponent)
        if agentType == .unknown, lines.count >= 2,
           let secondLine = lines.dropFirst().first,
           let secondEntry = try? JSONDecoder().decode(AgentEntry.self, from: Data(secondLine.utf8)),
           let assistantContent = secondEntry.message?.content {
            agentType = inferAgentType(from: assistantContent)
        }

        // Determine status based on file attributes and content
        let status = determineStatus(url: url, lines: lines)

        return Agent(
            id: agentId,
            parentSessionId: actualSessionId,
            type: agentType,
            status: status
        )
    }

    private func extractAgentId(from filename: String) -> String {
        // Format: agent-a{type}-{id}.jsonl or agent-{id}.jsonl
        let name = filename
            .replacingOccurrences(of: "agent-", with: "")
            .replacingOccurrences(of: ".jsonl", with: "")

        // If format is a{type}-{id}, extract just the id part
        if name.hasPrefix("a") {
            let parts = name.dropFirst().split(separator: "-", maxSplits: 1)
            if parts.count == 2 {
                return String(parts[1])
            }
        }
        return name
    }

    private func extractAgentType(from filename: String) -> AgentType {
        // Format: agent-a{type}-{id}.jsonl
        let name = filename
            .replacingOccurrences(of: "agent-", with: "")
            .replacingOccurrences(of: ".jsonl", with: "")

        // If format is a{type}-{id}, extract the type
        if name.hasPrefix("a") {
            let withoutPrefix = name.dropFirst()
            if let dashIndex = withoutPrefix.firstIndex(of: "-") {
                let typePart = String(withoutPrefix[..<dashIndex])
                return AgentType(from: typePart)
            }
        }
        return .unknown
    }

    private func inferAgentType(from content: [MessageContent]) -> AgentType {
        let text = content.compactMap { $0.text }.joined(separator: " ").lowercased()

        if text.contains("read-only mode") || text.contains("search and explore") {
            return .explore
        } else if text.contains("design implementation plans") || text.contains("plan mode") {
            return .plan
        } else if text.contains("bash") || text.contains("command execution") {
            return .bash
        } else if text.contains("code review") || text.contains("reviewing") {
            return .codeReview
        } else if text.contains("general-purpose") || text.contains("multi-step tasks") {
            return .general
        }

        return .unknown
    }

    private func determineStatus(url: URL, lines: [String]) -> AgentStatus {
        // Check file modification time - if recently modified, likely still running
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age < 120 { // Modified in last 2 minutes (agents can "think" for a while)
                return .running
            }
        }

        // Check last line for completion indicators
        if let lastLine = lines.last,
           let lastEntry = try? JSONDecoder().decode(AgentEntry.self, from: Data(lastLine.utf8)) {
            if let stopReason = lastEntry.message?.stopReason {
                if stopReason == "end_turn" {
                    return .completed
                }
            }
        }

        return .completed // Default to completed for old files
    }
}

// MARK: - JSON Models for parsing agent files

private struct AgentEntry: Decodable, Sendable {
    let agentId: String?
    let sessionId: String?
    let message: AgentMessage?
}

private struct AgentMessage: Decodable, Sendable {
    let role: String?
    let content: [MessageContent]?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case stopReason = "stop_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)

        // Content can be string or array
        if let contentArray = try? container.decode([MessageContent].self, forKey: .content) {
            content = contentArray
        } else if let contentString = try? container.decode(String.self, forKey: .content) {
            content = [MessageContent(type: "text", text: contentString)]
        } else {
            content = nil
        }
    }
}

private struct MessageContent: Decodable, Sendable {
    let type: String?
    let text: String?
}
