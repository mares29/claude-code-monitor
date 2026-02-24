import SwiftUI

struct AgentBlock: View {
    let agent: AgentSummary
    let isExpanded: Bool
    let onToggle: () -> Void

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
                        .foregroundStyle(.brown)

                    Text(agent.description ?? agent.type.displayName)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    statusBadge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.brown.opacity(0.08))
            .cornerRadius(6)

            // Expanded content
            if isExpanded {
                if let content = agent.resultContent, !content.isEmpty {
                    MarkdownText(content)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                } else if agent.status == .running {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Agent is working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 8)
                } else {
                    Text("No output")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                }
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
            .foregroundStyle(Color.accentColor)
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

}
