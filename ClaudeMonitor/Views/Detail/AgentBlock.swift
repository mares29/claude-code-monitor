import SwiftUI

struct AgentBlock: View {
    let agent: AgentSummary
    let isExpanded: Bool
    let onToggle: () -> Void

    // Agent turns loaded on expand
    @State private var agentTurns: [ConversationTurn] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "cpu")
                        .foregroundStyle(.purple)

                    Text("Agent: \(agent.type.displayName)")
                        .font(.body)

                    if agent.turnCount > 0 {
                        Text("(\(agent.turnCount) turns)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(6)

            // Expanded content
            if isExpanded {
                if isLoading {
                    ProgressView()
                        .padding()
                } else if agentTurns.isEmpty {
                    Text("No activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(agentTurns) { turn in
                            MiniTurnRow(turn: turn)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && agentTurns.isEmpty {
                loadAgentTurns()
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch agent.status {
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Running")
                    .font(.caption)
            }
            .foregroundStyle(.blue)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .cancelled:
            Label("Cancelled", systemImage: "stop.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func loadAgentTurns() {
        // TODO: Load from agent-{type}-{id}.jsonl file
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isLoading = false
        }
    }
}

/// Compact turn display for nested agent view
private struct MiniTurnRow: View {
    let turn: ConversationTurn

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                if let text = turn.text {
                    Text(text)
                        .font(.caption)
                        .lineLimit(2)
                }

                if !turn.toolCalls.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(turn.toolCalls.prefix(3)) { tool in
                            Text(tool.name)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                        if turn.toolCalls.count > 3 {
                            Text("+\(turn.toolCalls.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: turn.timestamp)
    }
}
