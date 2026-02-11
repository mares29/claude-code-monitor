import SwiftUI

struct ConsolePanel: View {
    @Bindable var state: MonitorState
    @State private var isExpanded = false
    @State private var filter: LogLevel? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text("Console")
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)

                Text("\(filteredLogs.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                if isExpanded {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag(LogLevel?.none)
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(LogLevel?.some(level))
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Button {
                        state.logEntries.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear console")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            // Log content
            if isExpanded {
                Divider()

                List(filteredLogs) { entry in
                    ConsoleRow(entry: entry)
                }
                .listStyle(.plain)
                .frame(minHeight: 100, maxHeight: 200)
            }
        }
    }

    private var filteredLogs: [LogEntry] {
        state.logEntries.filter { entry in
            filter == nil || entry.level == filter
        }
    }
}

struct ConsoleRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(entry.level.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(levelColor)
                .frame(width: 45, alignment: .leading)

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .listRowBackground(entry.level == .error ? Color.red.opacity(0.1) : nil)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .primary
        case .error: .red
        }
    }
}

#Preview {
    ConsolePanel(state: {
        let s = MonitorState()
        s.addLogEntry(LogEntry(id: UUID(), timestamp: Date(), level: .debug, message: "Test debug", sessionId: nil))
        s.addLogEntry(LogEntry(id: UUID(), timestamp: Date(), level: .info, message: "Test info", sessionId: nil))
        s.addLogEntry(LogEntry(id: UUID(), timestamp: Date(), level: .error, message: "Test error", sessionId: nil))
        return s
    }())
}
