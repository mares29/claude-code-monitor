import SwiftUI

// MARK: - User Message Divider

struct UserMessageDivider: View {
    let text: String
    let timestamp: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top spacing to separate from previous turn
            Spacer()
                .frame(height: 10)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("You")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(timeString)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: timestamp)
    }
}

// MARK: - Assistant Text Block

struct AssistantTextBlock: View {
    let text: String
    let timestamp: Date
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .leading)

                    Image(systemName: "text.bubble")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(isExpanded ? "Assistant response" : snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            if isExpanded {
                MarkdownText(text, font: .body)
                    .padding(.leading, 64)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var snippet: String {
        String(text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: timestamp)
    }
}

// MARK: - Tool Icons

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
    case "bash": .brown
    case "task", "taskoutput", "taskstop": .brown
    case "taskcreate", "taskupdate", "tasklist", "taskget": .brown
    case "skill": .orange
    case "askuserquestion": .green
    default: .accentColor
    }
}
