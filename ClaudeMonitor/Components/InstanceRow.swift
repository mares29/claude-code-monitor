import SwiftUI

struct InstanceRow: View {
    let instance: ClaudeInstance
    let sparkline: String?
    let isSelected: Bool
    let currentAction: String?
    let currentModel: String?
    let latestTokens: TokenUsage?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: Status + Name + Badges + Relative time
            HStack(spacing: 6) {
                if instance.isDangerousMode {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("Running with --dangerously-skip-permissions")
                }

                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let terminal = instance.terminalApp {
                    Text(terminal)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                Text(instance.startTime, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Line 2: Current action + Sparkline
            HStack(spacing: 6) {
                Text(currentAction ?? instance.activityState.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: currentAction)

                Spacer()

                if let spark = sparkline, !spark.isEmpty {
                    SparklineView(data: spark.sparklineToData(), tint: .accentColor)
                        .frame(width: 60, height: 14)
                        .offset(y: 10)
                }
            }

            // Line 3: Model + Tokens + CPU + Memory
            HStack(spacing: 0) {
                statsLine
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06))
            }
        }
        .animation(.easeInOut(duration: 0.6), value: instance.isActive)
        .mask {
            // Fade ratio: 0 = fully visible, 1 = full fade effect
            let fade = instance.isActive ? 0.0 : 1.0
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(1.0 - fade * 0.3), location: 0),
                    .init(color: .white.opacity(1.0 - fade * 0.7), location: 0.5),
                    .init(color: .white.opacity(1.0 - fade), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .animation(.easeInOut(duration: 0.6), value: instance.isActive)
        .contentShape(Rectangle())
    }

    // MARK: - Stats Line

    @ViewBuilder
    private var statsLine: some View {
        let parts = buildStatsParts()
        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
            if index > 0 {
                Text(" · ")
                    .foregroundStyle(.quaternary)
            }
            Text(part)
                .contentTransition(.numericText())
        }
    }

    private func buildStatsParts() -> [String] {
        var parts: [String] = []

        if let model = currentModel {
            parts.append(model)
        }

        if let tokens = latestTokens {
            let inK = String(format: "↓%.0fk", Double(tokens.totalInput) / 1000)
            let outK = String(format: "↑%.0fk", Double(tokens.outputTokens) / 1000)
            parts.append("\(inK) \(outK)")
        }

        if instance.cpuPercent > 0 {
            parts.append(String(format: "%.0f%%", instance.cpuPercent))
        }

        if instance.memoryMB > 0 {
            parts.append("\(instance.memoryMB) MB")
        }

        return parts
    }

    // MARK: - Computed

    private var displayName: String {
        URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
    }

}

#Preview {
    List {
        InstanceRow(
            instance: ClaudeInstance(
                pid: 1234,
                workingDirectory: "/Users/test/my-project",
                arguments: ["claude", "--dangerously-skip-permissions"],
                activityState: .working,
                terminalApp: "Warp",
                cpuPercent: 8.5,
                memoryMB: 180,
                tty: "ttys001"
            ),
            sparkline: "▁▂▃▅▇▅▃▂",
            isSelected: true,
            currentAction: "Edit Components/InstanceRow.swift",
            currentModel: "OPUS 4.5",
            latestTokens: TokenUsage(inputTokens: 12500, outputTokens: 3200, cacheReadTokens: 8000, cacheCreationTokens: 0)
        )
        InstanceRow(
            instance: ClaudeInstance(
                pid: 5678,
                workingDirectory: "/Users/test/another-project",
                arguments: ["claude", "--continue", "--verbose"],
                activityState: .idle,
                terminalApp: "iTerm",
                cpuPercent: 0.0,
                memoryMB: 95,
                tty: "ttys002"
            ),
            sparkline: nil,
            isSelected: false,
            currentAction: nil,
            currentModel: "SONNET",
            latestTokens: nil
        )
    }
    .listStyle(.sidebar)
}
