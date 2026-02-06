import SwiftUI

struct ToolCallRow: View {
    let toolCall: ToolCall
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact row
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                        .frame(width: 16)

                    Text(toolCall.name)
                        .font(.body)
                        .frame(width: 50, alignment: .leading)

                    Text(displayTarget)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if let result = toolCall.result {
                        Image(systemName: result.isSuccess ? "checkmark" : "xmark")
                            .font(.caption)
                            .foregroundStyle(result.isSuccess ? .green : .red)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Input
                    GroupBox("Input") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(toolCall.input.rawJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }

                    // Result
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
                .padding(.leading, 28)
                .padding(.vertical, 4)
            }
        }
    }

    private var iconName: String {
        switch toolCall.name.lowercased() {
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

    private var iconColor: Color {
        switch toolCall.name.lowercased() {
        case "write", "edit": .orange
        case "bash": .purple
        case "task", "taskoutput", "taskstop": .indigo
        case "taskcreate", "taskupdate", "tasklist", "taskget": .teal
        case "skill": .pink
        case "askuserquestion": .green
        default: .blue
        }
    }

    private var displayTarget: String {
        if let path = toolCall.input.filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let cmd = toolCall.input.command {
            let firstLine = cmd.components(separatedBy: "\n").first ?? cmd
            return String(firstLine.prefix(50))
        }
        if let pattern = toolCall.input.pattern {
            return pattern
        }
        return "—"
    }
}
