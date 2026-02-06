import SwiftUI

struct TurnCard: View {
    let turn: ConversationTurn
    @Binding var isTextExpanded: Bool
    @Binding var expandedToolIds: Set<String>
    @Binding var expandedAgentIds: Set<String>

    private let maxCollapsedLines = 3

    private var isUser: Bool { turn.role == .user }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if isUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(timeString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if let usage = turn.tokenUsage {
                    Text(usage.formattedBadge)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.05))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Text section
                if let text = turn.text, !text.isEmpty {
                    textSection(text)
                }

                // Tool calls (assistant only)
                if !turn.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(turn.toolCalls) { tool in
                            ToolCallRow(
                                toolCall: tool,
                                isExpanded: expandedToolIds.contains(tool.id),
                                onToggle: { toggleTool(tool.id) }
                            )
                        }
                    }
                }

                // Agent spawns (assistant only)
                if !turn.agentSpawns.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(turn.agentSpawns) { agent in
                            AgentBlock(
                                agent: agent,
                                isExpanded: expandedAgentIds.contains(agent.id),
                                onToggle: { toggleAgent(agent.id) }
                            )
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isUser ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func textSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isTextExpanded ? text : truncatedText(text))
                .font(.body)
                .textSelection(.enabled)

            if shouldTruncate(text) {
                Button(action: { isTextExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isTextExpanded ? "chevron.up" : "chevron.down")
                        Text(isTextExpanded ? "Show less" : "Show more")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func truncatedText(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count <= maxCollapsedLines {
            return text
        }
        return lines.prefix(maxCollapsedLines).joined(separator: "\n") + "..."
    }

    private func shouldTruncate(_ text: String) -> Bool {
        text.components(separatedBy: "\n").count > maxCollapsedLines
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: turn.timestamp)
    }

    private func toggleTool(_ id: String) {
        if expandedToolIds.contains(id) {
            expandedToolIds.remove(id)
        } else {
            expandedToolIds.insert(id)
        }
    }

    private func toggleAgent(_ id: String) {
        if expandedAgentIds.contains(id) {
            expandedAgentIds.remove(id)
        } else {
            expandedAgentIds.insert(id)
        }
    }
}
