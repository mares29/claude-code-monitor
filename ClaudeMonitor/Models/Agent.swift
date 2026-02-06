import Foundation

struct Agent: Identifiable, Hashable, Sendable {
    let id: String
    let parentSessionId: String
    let type: AgentType
    var status: AgentStatus
    let slug: String?

    init(id: String, parentSessionId: String, type: AgentType, status: AgentStatus = .running, slug: String? = nil) {
        self.id = id
        self.parentSessionId = parentSessionId
        self.type = type
        self.status = status
        self.slug = slug
    }

    /// Parse agent type from filename like "agent-explore-abc123.jsonl"
    static func parseType(from filename: String) -> AgentType {
        // Format: agent-{type}-{shortId}.jsonl
        let components = filename
            .replacingOccurrences(of: "agent-", with: "")
            .replacingOccurrences(of: ".jsonl", with: "")
            .split(separator: "-")

        guard components.count >= 1 else { return .unknown }
        return AgentType(from: String(components[0]))
    }
}
