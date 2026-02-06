import SwiftUI

struct NowPlayingBanner: View {
    let turn: ConversationTurn?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon + action description
            if let turn {
                Image(systemName: actionIcon(for: turn))
                    .font(.system(size: 14))
                    .foregroundStyle(actionColor(for: turn))

                Text(actionText(for: turn))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("Waiting for activity...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Token badge
            if let usage = turn?.tokenUsage {
                Text(usage.formattedBadge)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func actionText(for turn: ConversationTurn) -> String {
        // Prefer showing the most recent tool call
        if let lastTool = turn.toolCalls.last {
            let target = displayTarget(for: lastTool)
            return "\(lastTool.name) \(target)"
        }
        // Fall back to text snippet
        if let text = turn.text, !text.isEmpty {
            let snippet = text.prefix(80).replacingOccurrences(of: "\n", with: " ")
            return turn.role == .user ? "User: \(snippet)" : String(snippet)
        }
        // Agent spawns
        if let agent = turn.agentSpawns.last {
            return "Agent: \(agent.type.displayName)"
        }
        return "Thinking..."
    }

    private func actionIcon(for turn: ConversationTurn) -> String {
        if let lastTool = turn.toolCalls.last {
            return toolIconName(lastTool.name)
        }
        if turn.role == .user {
            return "person.fill"
        }
        if !turn.agentSpawns.isEmpty {
            return "cpu"
        }
        return "text.bubble"
    }

    private func actionColor(for turn: ConversationTurn) -> Color {
        if let lastTool = turn.toolCalls.last {
            return toolIconColor(lastTool.name)
        }
        if turn.role == .user { return .blue }
        if !turn.agentSpawns.isEmpty { return .purple }
        return .secondary
    }

    private func displayTarget(for tool: ToolCall) -> String {
        if let path = tool.input.filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let cmd = tool.input.command {
            return String(cmd.components(separatedBy: "\n").first?.prefix(40) ?? "")
        }
        if let pattern = tool.input.pattern {
            return pattern
        }
        return ""
    }
}

// MARK: - Shared icon/color logic (extracted from ToolCallRow for reuse)

func toolIconName(_ name: String) -> String {
    switch name.lowercased() {
    case "read": "doc.text"
    case "write": "doc.badge.plus"
    case "edit": "pencil"
    case "bash": "terminal"
    case "grep": "magnifyingglass"
    case "glob": "folder.badge.gearshape"
    case "webfetch", "websearch": "globe"
    case "task": "person.2.circle"
    case "taskoutput": "arrow.down.doc"
    case "taskstop": "stop.circle"
    case "taskcreate": "plus.square"
    case "taskupdate": "arrow.triangle.2.circlepath"
    case "tasklist", "taskget": "list.bullet"
    case "skill": "sparkles"
    case "askuserquestion": "questionmark.bubble"
    case "enterplanmode", "exitplanmode": "map"
    case "notebookedit": "book"
    default: "gearshape"
    }
}

func toolIconColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "write", "edit": .orange
    case "bash": .purple
    case "task", "taskoutput", "taskstop": .indigo
    case "taskcreate", "taskupdate", "tasklist", "taskget": .teal
    case "skill": .pink
    case "askuserquestion": .green
    default: .blue
    }
}
