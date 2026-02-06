import SwiftUI

struct TimelineRow: View {
    let toolCall: ToolCall
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact single-line
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    // Timestamp
                    Text(timeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .leading)

                    // Status indicator
                    if let result = toolCall.result {
                        Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(result.isSuccess ? .green : .red)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12)
                    }

                    // Tool icon + name
                    Image(systemName: toolIconName(toolCall.name))
                        .font(.system(size: 11))
                        .foregroundStyle(toolIconColor(toolCall.name))
                        .frame(width: 14)

                    Text(toolCall.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 56, alignment: .leading)

                    // Target
                    Text(displayTarget)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            // Expanded details (same GroupBox pattern as ToolCallRow)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    GroupBox("Input") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(toolCall.input.rawJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }

                    if let result = toolCall.result {
                        GroupBox(result.isSuccess ? "Output" : "Error") {
                            ScrollView {
                                Text(result.content ?? result.errorMessage ?? "—")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(result.isSuccess ? .primary : .red)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                }
                .padding(.leading, 64)
                .padding(.vertical, 4)
            }
        }
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: toolCall.timestamp)
    }

    private var displayTarget: String {
        if let path = toolCall.input.filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let cmd = toolCall.input.command {
            let firstLine = cmd.components(separatedBy: "\n").first ?? cmd
            return String(firstLine.prefix(60))
        }
        if let pattern = toolCall.input.pattern {
            return pattern
        }
        return "—"
    }
}
