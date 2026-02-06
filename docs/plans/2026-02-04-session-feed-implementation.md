# Session Feed Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ActivityFeedView with a session JSONL-based feed showing conversation turns, tool calls, token usage, and agent activity with real-time updates.

**Architecture:** Parse session JSONL into ConversationTurn objects grouped by assistant message. Each turn contains tool calls and results. File watcher via DispatchSource triggers incremental parsing. Agents displayed as collapsed blocks.

**Tech Stack:** SwiftUI, DispatchSource for file watching, JSONDecoder for JSONL parsing

---

## Task 1: Session Data Models

**Files:**

- Create: `ClaudeMonitor/Models/SessionModels.swift`

**Step 1: Create SessionModels.swift with all types**

```swift
import Foundation

// MARK: - Core Types

struct ConversationTurn: Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let text: String?
    let toolCalls: [ToolCall]
    let tokenUsage: TokenUsage?
    let agentSpawns: [AgentSummary]

    init(
        id: String,
        timestamp: Date,
        text: String? = nil,
        toolCalls: [ToolCall] = [],
        tokenUsage: TokenUsage? = nil,
        agentSpawns: [AgentSummary] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.toolCalls = toolCalls
        self.tokenUsage = tokenUsage
        self.agentSpawns = agentSpawns
    }
}

struct ToolCall: Identifiable, Sendable {
    let id: String
    let name: String
    let input: ToolCallInput
    let result: ToolCallResult?
    let timestamp: Date
}

struct ToolCallInput: Sendable {
    let filePath: String?
    let command: String?
    let pattern: String?
    let rawJSON: String  // Full input for expandable view
}

struct ToolCallResult: Sendable {
    let isSuccess: Bool
    let content: String?
    let errorMessage: String?
}

struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int

    var totalInput: Int { inputTokens + cacheReadTokens + cacheCreationTokens }

    var formattedBadge: String {
        let inK = String(format: "%.1fk", Double(totalInput) / 1000)
        let outK = String(format: "%.1fk", Double(outputTokens) / 1000)
        let cachedK = String(format: "%.1fk", Double(cacheReadTokens) / 1000)
        return "↓\(inK) ↑\(outK) ⚡\(cachedK)"
    }
}

struct AgentSummary: Identifiable, Sendable {
    let id: String
    let type: AgentType
    var turnCount: Int
    var status: AgentStatus
    let parentTurnId: String
}

// MARK: - JSONL Decoding Models

struct SessionEntry: Decodable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let timestamp: String?
    let message: SessionMessage?
    let isSidechain: Bool?
    let toolUseID: String?

    var parsedTimestamp: Date? {
        guard let ts = timestamp else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: ts)
    }
}

struct SessionMessage: Decodable {
    let role: String?
    let content: [SessionContent]?
    let usage: SessionUsage?
    let model: String?
}

struct SessionContent: Decodable {
    let type: String
    let text: String?
    let name: String?
    let input: [String: AnyCodable]?
    let toolUseId: String?
    let content: AnyCodableValue?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type, text, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

struct SessionUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

// MARK: - AnyCodable helpers for dynamic JSON

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    var stringValue: String? { value as? String }
}

enum AnyCodableValue: Decodable {
    case string(String)
    case array([AnyCodableValue])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else {
            self = .other
        }
    }

    var asString: String? {
        switch self {
        case .string(let s): return s
        case .array(let arr): return arr.compactMap(\.asString).joined(separator: "\n")
        case .other: return nil
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Models/SessionModels.swift
git commit -m "feat(models): add session JSONL data models"
```

---

## Task 2: Session Parser Service

**Files:**

- Create: `ClaudeMonitor/Services/SessionParser.swift`

**Step 1: Create SessionParser.swift**

```swift
import Foundation

struct SessionParser: Sendable {

    /// Parse session JSONL file into conversation turns
    func parse(sessionPath: URL) -> [ConversationTurn] {
        guard let data = try? Data(contentsOf: sessionPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseContent(content)
    }

    /// Parse from offset, return turns and new offset
    func parseIncremental(sessionPath: URL, fromOffset: UInt64) -> (turns: [ConversationTurn], newOffset: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: sessionPath) else {
            return ([], fromOffset)
        }
        defer { try? handle.close() }

        try? handle.seek(toOffset: fromOffset)
        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return ([], fromOffset)
        }

        let turns = parseContent(content)
        let newOffset = fromOffset + UInt64(data.count)
        return (turns, newOffset)
    }

    // MARK: - Private

    private func parseContent(_ content: String) -> [ConversationTurn] {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var entries: [SessionEntry] = []
        let decoder = JSONDecoder()

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(SessionEntry.self, from: data) else {
                continue
            }
            entries.append(entry)
        }

        return buildTurns(from: entries)
    }

    private func buildTurns(from entries: [SessionEntry]) -> [ConversationTurn] {
        // Group: assistant messages are turn anchors
        // Tool results (user messages with tool_result) attach to their parent

        var turns: [ConversationTurn] = []
        var toolResults: [String: ToolCallResult] = [:] // toolUseId -> result

        // First pass: collect tool results
        for entry in entries where entry.type == "user" {
            guard let content = entry.message?.content else { continue }
            for item in content where item.type == "tool_result" {
                if let toolId = item.toolUseId {
                    let resultContent = item.content?.asString
                    let isError = item.isError ?? false
                    toolResults[toolId] = ToolCallResult(
                        isSuccess: !isError,
                        content: isError ? nil : resultContent,
                        errorMessage: isError ? resultContent : nil
                    )
                }
            }
        }

        // Second pass: build turns from assistant messages
        for entry in entries where entry.type == "assistant" {
            guard let uuid = entry.uuid,
                  let message = entry.message,
                  let content = message.content else { continue }

            let timestamp = entry.parsedTimestamp ?? Date()

            // Extract text
            let textParts = content.compactMap { item -> String? in
                item.type == "text" ? item.text : nil
            }
            let text = textParts.isEmpty ? nil : textParts.joined(separator: "\n")

            // Extract tool calls
            var toolCalls: [ToolCall] = []
            var agentSpawns: [AgentSummary] = []

            for item in content where item.type == "tool_use" {
                guard let name = item.name,
                      let toolId = item.toolUseId ?? item.input?["id"]?.stringValue else { continue }

                let input = item.input ?? [:]
                let inputJSON = (try? JSONSerialization.data(withJSONObject: input.mapValues { $0.value }))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                let filePath = input["file_path"]?.stringValue ?? input["path"]?.stringValue
                let command = input["command"]?.stringValue
                let pattern = input["pattern"]?.stringValue

                let toolInput = ToolCallInput(
                    filePath: filePath,
                    command: command,
                    pattern: pattern,
                    rawJSON: inputJSON
                )

                // Check for Task tool (agent spawn)
                if name == "Task" {
                    let agentType = input["subagent_type"]?.stringValue ?? "unknown"
                    agentSpawns.append(AgentSummary(
                        id: toolId,
                        type: AgentType(from: agentType),
                        turnCount: 0,
                        status: .running,
                        parentTurnId: uuid
                    ))
                } else {
                    toolCalls.append(ToolCall(
                        id: toolId,
                        name: name,
                        input: toolInput,
                        result: toolResults[toolId],
                        timestamp: timestamp
                    ))
                }
            }

            // Extract token usage
            var tokenUsage: TokenUsage? = nil
            if let usage = message.usage {
                tokenUsage = TokenUsage(
                    inputTokens: usage.inputTokens ?? 0,
                    outputTokens: usage.outputTokens ?? 0,
                    cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                    cacheCreationTokens: usage.cacheCreationInputTokens ?? 0
                )
            }

            turns.append(ConversationTurn(
                id: uuid,
                timestamp: timestamp,
                text: text,
                toolCalls: toolCalls,
                tokenUsage: tokenUsage,
                agentSpawns: agentSpawns
            ))
        }

        // Sort newest first
        return turns.sorted { $0.timestamp > $1.timestamp }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Services/SessionParser.swift
git commit -m "feat(services): add session JSONL parser"
```

---

## Task 3: Session File Watcher

**Files:**

- Create: `ClaudeMonitor/Services/SessionFileWatcher.swift`

**Step 1: Create SessionFileWatcher.swift**

```swift
import Foundation

final class SessionFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "SessionFileWatcher", qos: .utility)

    func watch(path: URL, onChange: @escaping () -> Void) {
        stopWatching()

        fileDescriptor = open(path.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )

        source?.setEventHandler {
            DispatchQueue.main.async {
                onChange()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    deinit {
        stopWatching()
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Services/SessionFileWatcher.swift
git commit -m "feat(services): add DispatchSource file watcher"
```

---

## Task 4: ToolCallRow Component

**Files:**

- Create: `ClaudeMonitor/Views/Detail/ToolCallRow.swift`

**Step 1: Create ToolCallRow.swift**

```swift
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
                                    .foregroundStyle(result.isSuccess ? .primary : .red)
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
        case "glob": "folder"
        case "webfetch", "websearch": "globe"
        default: "gearshape"
        }
    }

    private var iconColor: Color {
        switch toolCall.name.lowercased() {
        case "write", "edit": .orange
        case "bash": .purple
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
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Views/Detail/ToolCallRow.swift
git commit -m "feat(views): add expandable ToolCallRow component"
```

---

## Task 5: AgentBlock Component

**Files:**

- Create: `ClaudeMonitor/Views/Detail/AgentBlock.swift`

**Step 1: Create AgentBlock.swift**

```swift
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
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Views/Detail/AgentBlock.swift
git commit -m "feat(views): add collapsible AgentBlock component"
```

---

## Task 6: TurnCard Component

**Files:**

- Create: `ClaudeMonitor/Views/Detail/TurnCard.swift`

**Step 1: Create TurnCard.swift**

```swift
import SwiftUI

struct TurnCard: View {
    let turn: ConversationTurn
    @Binding var isTextExpanded: Bool
    @Binding var expandedToolIds: Set<String>
    @Binding var expandedAgentIds: Set<String>

    private let maxCollapsedLines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
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
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Text section
                if let text = turn.text, !text.isEmpty {
                    textSection(text)
                }

                // Tool calls
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

                // Agent spawns
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
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
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
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Views/Detail/TurnCard.swift
git commit -m "feat(views): add TurnCard component with expandable sections"
```

---

## Task 7: SessionFeedView Main View

**Files:**

- Create: `ClaudeMonitor/Views/Detail/SessionFeedView.swift`

**Step 1: Create SessionFeedView.swift**

```swift
import SwiftUI

struct SessionFeedView: View {
    let instance: ClaudeInstance

    @State private var turns: [ConversationTurn] = []
    @State private var expandedTextTurns: Set<String> = []
    @State private var expandedToolIds: Set<String> = []
    @State private var expandedAgentIds: Set<String> = []
    @State private var fileOffset: UInt64 = 0

    private let parser = SessionParser()
    private let watcher = SessionFileWatcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()

            // Feed
            if turns.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Waiting for conversation data...")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(turns) { turn in
                            TurnCard(
                                turn: turn,
                                isTextExpanded: binding(for: turn.id),
                                expandedToolIds: $expandedToolIds,
                                expandedAgentIds: $expandedAgentIds
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadSession()
            startWatching()
        }
        .onDisappear {
            watcher.stopWatching()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text(instance.workingDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var displayName: String {
        URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
    }

    private var statusLine: String {
        var parts: [String] = []

        if instance.isActive {
            parts.append("Running for \(formattedDuration)")
        } else {
            parts.append("Idle")
        }

        if !instance.agents.isEmpty {
            parts.append("\(instance.agents.count) agent\(instance.agents.count == 1 ? "" : "s")")
        }

        if instance.cpuPercent > 0 {
            parts.append(String(format: "%.0f%% CPU", instance.cpuPercent))
        }

        if instance.memoryMB > 0 {
            parts.append("\(instance.memoryMB) MB")
        }

        return parts.joined(separator: " · ")
    }

    private var formattedDuration: String {
        let elapsed = Int(Date().timeIntervalSince(instance.startTime))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    private func binding(for turnId: String) -> Binding<Bool> {
        Binding(
            get: { expandedTextTurns.contains(turnId) },
            set: { expanded in
                if expanded {
                    expandedTextTurns.insert(turnId)
                } else {
                    expandedTextTurns.remove(turnId)
                }
            }
        )
    }

    private func loadSession() async {
        guard let sessionId = instance.sessionId else { return }
        let sessionPath = sessionFilePath(sessionId: sessionId)

        guard FileManager.default.fileExists(atPath: sessionPath.path) else { return }

        let (newTurns, newOffset) = parser.parseIncremental(sessionPath: sessionPath, fromOffset: 0)
        await MainActor.run {
            turns = newTurns
            fileOffset = newOffset
        }
    }

    private func startWatching() {
        guard let sessionId = instance.sessionId else { return }
        let sessionPath = sessionFilePath(sessionId: sessionId)

        watcher.watch(path: sessionPath) { [self] in
            Task {
                let (newTurns, newOffset) = parser.parseIncremental(sessionPath: sessionPath, fromOffset: fileOffset)
                await MainActor.run {
                    // Merge new turns, avoiding duplicates
                    let existingIds = Set(turns.map(\.id))
                    let uniqueNewTurns = newTurns.filter { !existingIds.contains($0.id) }
                    turns = (turns + uniqueNewTurns).sorted { $0.timestamp > $1.timestamp }
                    fileOffset = newOffset
                }
            }
        }
    }

    private func sessionFilePath(sessionId: String) -> URL {
        let projectsPath = ClaudeInstance.projectsPath(for: instance.workingDirectory)
        return URL(fileURLWithPath: "\(projectsPath)/\(sessionId).jsonl")
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Views/Detail/SessionFeedView.swift
git commit -m "feat(views): add SessionFeedView with file watching"
```

---

## Task 8: Integrate SessionFeedView into MainView

**Files:**

- Modify: `ClaudeMonitor/Views/MainView.swift`

**Step 1: Replace ActivityFeedView with SessionFeedView**

In MainView.swift, change both occurrences of `ActivityFeedView` to `SessionFeedView`:

```swift
// Line 35: Change from
ActivityFeedView(
    instance: instance,
    operations: state.recentOperations,
    sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] }
)

// To
SessionFeedView(instance: instance)
```

```swift
// Line 42: Change from
ActivityFeedView(
    instance: instance,
    operations: state.recentOperations,
    sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] }
)

// To
SessionFeedView(instance: instance)
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeMonitor/Views/MainView.swift
git commit -m "feat(views): integrate SessionFeedView into MainView"
```

---

## Task 9: Cleanup - Remove Old Files

**Files:**

- Delete: `ClaudeMonitor/Views/Detail/ActivityFeedView.swift`
- Delete: `ClaudeMonitor/Services/ToolOperationParser.swift`
- Modify: `ClaudeMonitor/Models/ActivityModels.swift` - remove ToolOperation
- Modify: `ClaudeMonitor/Models/MonitorState.swift` - remove recentOperations

**Step 1: Delete ActivityFeedView.swift**

```bash
rm ClaudeMonitor/Views/Detail/ActivityFeedView.swift
```

**Step 2: Delete ToolOperationParser.swift**

```bash
rm ClaudeMonitor/Services/ToolOperationParser.swift
```

**Step 3: Update ActivityModels.swift**

Remove `ToolOperation` struct and `ToolType` enum (lines 11-70). Keep `FilePosition`, `FileConflict`, `ConflictSeverity`, and session index types.

**Step 4: Update MonitorState.swift**

Remove:

- `var recentOperations: [ToolOperation] = []` (line 14)
- `private let maxRecentOps = 100` (line 19)
- `func addOperations(_ ops: [ToolOperation])` (lines 82-87)

**Step 5: Build to verify compilation**

Run: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove old ActivityFeedView and ToolOperation tracking"
```

---

## Task 10: Manual Testing

**Step 1: Build and run the app**

```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build
open build/Debug/ClaudeMonitor.app
```

**Step 2: Verify functionality**

1. Launch app with a Claude Code session running
2. Verify turns display in detail view
3. Verify token badges show on each turn
4. Verify text truncation and "Show more" works
5. Verify tool calls expand/collapse
6. Verify agent blocks show (if any agents spawned)
7. Verify real-time updates when new messages arrive

**Step 3: Commit any fixes needed**

---

## Summary

| Task | Description          | Files                    |
| ---- | -------------------- | ------------------------ |
| 1    | Session data models  | SessionModels.swift      |
| 2    | Session JSONL parser | SessionParser.swift      |
| 3    | File watcher         | SessionFileWatcher.swift |
| 4    | Tool call row        | ToolCallRow.swift        |
| 5    | Agent block          | AgentBlock.swift         |
| 6    | Turn card            | TurnCard.swift           |
| 7    | Session feed view    | SessionFeedView.swift    |
| 8    | MainView integration | MainView.swift           |
| 9    | Cleanup old files    | Remove 2 files, modify 2 |
| 10   | Manual testing       | Verify all features      |
