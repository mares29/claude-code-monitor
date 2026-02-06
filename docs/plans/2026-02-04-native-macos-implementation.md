# Native macOS Redesign - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign Claude Monitor to follow Apple HIG - native List/NavigationSplitView, system colors, activity feed focus.

**Architecture:** Replace custom Theme/Cards with system styles. Sidebar shows instances, detail shows activity feed, collapsible console at bottom. Menu bar mirrors sidebar.

**Tech Stack:** SwiftUI, NavigationSplitView, native List, system colors, SF Symbols.

---

## Task 1: Remove Custom Theme

**Files:**

- Delete: `ClaudeMonitor/Theme/Theme.swift`
- Delete: `ClaudeMonitor/Components/CardView.swift`
- Delete: `ClaudeMonitor/Components/MetricCard.swift`

**Step 1: Delete files**

```bash
rm ClaudeMonitor/ClaudeMonitor/Theme/Theme.swift
rm ClaudeMonitor/ClaudeMonitor/Components/CardView.swift
rm ClaudeMonitor/ClaudeMonitor/Components/MetricCard.swift
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove custom theme and card components"
```

---

## Task 2: Update ToolType Icons

**Files:**

- Modify: `ClaudeMonitor/Models/ActivityModels.swift`

**Step 1: Update ToolType enum with SF Symbol icons**

Replace the `icon` property in `ToolType`:

```swift
enum ToolType: String, Sendable, CaseIterable {
    case read
    case write
    case edit
    case bash
    case grep
    case glob
    case search
    case task

    var icon: String {
        switch self {
        case .read: "doc.text"
        case .write: "doc.badge.plus"
        case .edit: "pencil"
        case .bash: "terminal"
        case .grep: "magnifyingglass"
        case .glob: "folder"
        case .search: "magnifyingglass"
        case .task: "gearshape.2"
        }
    }

    var label: String {
        switch self {
        case .read: "Read"
        case .write: "Write"
        case .edit: "Edit"
        case .bash: "Bash"
        case .grep: "Grep"
        case .glob: "Glob"
        case .search: "Search"
        case .task: "Agent"
        }
    }

    var isWriteOperation: Bool {
        self == .write || self == .edit
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: BUILD SUCCEEDED (with errors from missing Theme references - that's fine)

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Models/ActivityModels.swift
git commit -m "feat: update ToolType with SF Symbol icons"
```

---

## Task 3: Create InstanceRow Component

**Files:**

- Create: `ClaudeMonitor/Components/InstanceRow.swift`
- Delete: `ClaudeMonitor/Components/InstanceCard.swift`

**Step 1: Create InstanceRow.swift**

```swift
import SwiftUI

struct InstanceRow: View {
    let instance: ClaudeInstance
    let sparkline: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 10))
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Mini sparkline
                if let spark = sparkline, !spark.isEmpty {
                    Text(spark)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var displayName: String {
        URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
    }

    private var statusIcon: String {
        if hasRecentError {
            return "exclamationmark.circle.fill"
        }
        return instance.isActive ? "circle.fill" : "circle"
    }

    private var statusColor: Color {
        if hasRecentError {
            return .yellow
        }
        return instance.isActive ? .blue : .gray
    }

    // TODO: Wire up error detection from state
    private var hasRecentError: Bool {
        false
    }
}

#Preview {
    List {
        InstanceRow(
            instance: ClaudeInstance(
                pid: 1234,
                workingDirectory: "/Users/test/my-project",
                isActive: true
            ),
            sparkline: "▁▂▃▅▇▅▃▂",
            isSelected: true
        )
        InstanceRow(
            instance: ClaudeInstance(
                pid: 5678,
                workingDirectory: "/Users/test/another-project",
                isActive: false
            ),
            sparkline: nil,
            isSelected: false
        )
    }
    .listStyle(.sidebar)
}
```

**Step 2: Delete old InstanceCard**

```bash
rm ClaudeMonitor/ClaudeMonitor/Components/InstanceCard.swift
```

**Step 3: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: Errors about missing InstanceCard (will fix in Task 5)

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: replace InstanceCard with native InstanceRow"
```

---

## Task 4: Create ActivityFeedView

**Files:**

- Create: `ClaudeMonitor/Views/Detail/ActivityFeedView.swift`

**Step 1: Create ActivityFeedView.swift**

```swift
import SwiftUI

struct ActivityFeedView: View {
    let instance: ClaudeInstance
    let operations: [ToolOperation]
    let sparkline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            Divider()

            // Activity feed
            if filteredOperations.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "clock",
                    description: Text("Tool operations will appear here")
                )
            } else {
                List(filteredOperations) { op in
                    ActivityRow(operation: op)
                }
                .listStyle(.plain)
            }
        }
    }

    private var displayName: String {
        URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
    }

    private var statusLine: String {
        var parts: [String] = []

        if instance.isActive {
            parts.append("Running")
        } else {
            parts.append("Idle")
        }

        if !instance.agents.isEmpty {
            parts.append("\(instance.agents.count) agent\(instance.agents.count == 1 ? "" : "s")")
        }

        let inProgress = instance.tasks.filter { $0.status == .inProgress }.count
        if inProgress > 0 {
            parts.append("\(inProgress) task\(inProgress == 1 ? "" : "s") in progress")
        }

        return parts.joined(separator: " · ")
    }

    private var filteredOperations: [ToolOperation] {
        guard let sessionId = instance.sessionId else { return [] }
        return operations
            .filter { $0.sessionId == sessionId }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

struct ActivityRow: View {
    let operation: ToolOperation

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.timeFormatter.string(from: operation.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Image(systemName: operation.tool.icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(operation.tool.label)
                .font(.body)
                .frame(width: 50, alignment: .leading)

            Text(displayPath)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var displayPath: String {
        if let path = operation.filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "—"
    }

    private var iconColor: Color {
        operation.isWrite ? .orange : .blue
    }
}

#Preview {
    ActivityFeedView(
        instance: ClaudeInstance(
            pid: 1234,
            workingDirectory: "/Users/test/my-project",
            sessionId: "abc-123",
            agents: [Agent(id: "1", parentSessionId: "abc", type: .explore, status: .running, tasks: [])],
            tasks: [AgentTask(id: "1", subject: "Test", description: "", status: .inProgress, createdAt: Date())],
            isActive: true
        ),
        operations: [
            ToolOperation(timestamp: Date(), sessionId: "abc-123", agentId: nil, tool: .read, filePath: "/path/to/file.swift", isWrite: false),
            ToolOperation(timestamp: Date().addingTimeInterval(-5), sessionId: "abc-123", agentId: nil, tool: .edit, filePath: "/path/to/other.swift", isWrite: true),
        ],
        sparkline: "▁▂▃▅▇"
    )
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Views/Detail/ActivityFeedView.swift
git commit -m "feat: add ActivityFeedView for tool operation feed"
```

---

## Task 5: Rewrite MainView

**Files:**

- Modify: `ClaudeMonitor/Views/MainView.swift`

**Step 1: Replace MainView with native NavigationSplitView**

```swift
import SwiftUI

struct MainView: View {
    @Bindable var state: MonitorState
    @State private var selectedPid: Int?

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(state.instances, selection: $selectedPid) { instance in
                InstanceRow(
                    instance: instance,
                    sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] },
                    isSelected: selectedPid == instance.pid
                )
                .tag(instance.pid)
            }
            .listStyle(.sidebar)
            .navigationTitle("Instances")
        } detail: {
            // Detail
            VStack(spacing: 0) {
                if let pid = selectedPid,
                   let instance = state.instances.first(where: { $0.pid == pid }) {
                    ActivityFeedView(
                        instance: instance,
                        operations: state.recentOperations,
                        sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] }
                    )
                } else if let instance = state.instances.first {
                    ActivityFeedView(
                        instance: instance,
                        operations: state.recentOperations,
                        sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] }
                    )
                    .onAppear { selectedPid = instance.pid }
                } else {
                    ContentUnavailableView(
                        "No Instances",
                        systemImage: "terminal",
                        description: Text("No Claude Code instances are running")
                    )
                }

                // Console
                ConsolePanel(state: state)
            }
        }
        .onChange(of: state.instances) { _, newInstances in
            // Auto-select first instance if selection is invalid
            if selectedPid == nil || !newInstances.contains(where: { $0.pid == selectedPid }) {
                selectedPid = newInstances.first?.pid
            }
        }
    }
}

#Preview {
    MainView(state: MonitorState())
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: Error about missing ConsolePanel (will create next)

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Views/MainView.swift
git commit -m "feat: rewrite MainView with native NavigationSplitView"
```

---

## Task 6: Rewrite ConsoleView as ConsolePanel

**Files:**

- Modify: `ClaudeMonitor/Views/Console/ConsoleView.swift`

**Step 1: Rewrite ConsoleView.swift**

```swift
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
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Views/Console/ConsoleView.swift
git commit -m "feat: rewrite ConsoleView as collapsible ConsolePanel"
```

---

## Task 7: Rewrite MenuBarContent

**Files:**

- Modify: `ClaudeMonitor/Views/Menu/MenuBarContent.swift`

**Step 1: Rewrite MenuBarContent.swift**

```swift
import SwiftUI

struct MenuBarContent: View {
    @Bindable var state: MonitorState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Claude Monitor")
                    .font(.headline)

                Spacer()

                Image(systemName: overallStatusIcon)
                    .foregroundStyle(overallStatusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Instances
            if state.instances.isEmpty {
                HStack {
                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)
                    Text("No instances running")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(12)
            } else {
                ForEach(state.instances) { instance in
                    MenuInstanceRow(
                        instance: instance,
                        sparkline: instance.sessionId.flatMap { state.sessionSparklines[$0] }
                    ) {
                        openWindow(id: "main")
                    }
                }
            }

            Divider()

            // Actions
            Button {
                openWindow(id: "main")
            } label: {
                HStack {
                    Text("Open Monitor")
                    Spacer()
                    Text("⌘O")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 260)
    }

    private var overallStatusIcon: String {
        if state.instances.isEmpty {
            return "circle"
        }
        // TODO: Check for recent errors
        return state.instances.contains(where: \.isActive) ? "circle.fill" : "circle"
    }

    private var overallStatusColor: Color {
        if state.instances.isEmpty {
            return .gray
        }
        return state.instances.contains(where: \.isActive) ? .blue : .gray
    }
}

struct MenuInstanceRow: View {
    let instance: ClaudeInstance
    let sparkline: String?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: instance.isActive ? "circle.fill" : "circle")
                    .foregroundStyle(instance.isActive ? .blue : .gray)
                    .font(.system(size: 8))

                Text(displayName)
                    .lineLimit(1)

                Spacer()

                if let spark = sparkline, !spark.isEmpty {
                    Text(spark)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var displayName: String {
        URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
    }
}

#Preview {
    MenuBarContent(state: {
        let s = MonitorState()
        return s
    }())
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Views/Menu/MenuBarContent.swift
git commit -m "feat: simplify MenuBarContent with native styling"
```

---

## Task 8: Update StatusDot to Use System Colors

**Files:**

- Modify: `ClaudeMonitor/Components/StatusDot.swift`

**Step 1: Simplify StatusDot.swift**

```swift
import SwiftUI

enum StatusDotState {
    case idle
    case active
    case warning
    case error

    var color: Color {
        switch self {
        case .idle: .gray
        case .active: .blue
        case .warning: .yellow
        case .error: .red
        }
    }

    var shouldPulse: Bool {
        switch self {
        case .active, .warning: true
        case .idle, .error: false
        }
    }
}

struct StatusDot: View {
    let state: StatusDotState
    let size: CGFloat

    @State private var isPulsing = false

    init(state: StatusDotState, size: CGFloat = 8) {
        self.state = state
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(state == .idle ? Color.clear : state.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(state.color, lineWidth: state == .idle ? 1.5 : 0)
            )
            .scaleEffect(state.shouldPulse && isPulsing ? 1.15 : 1.0)
            .animation(
                state.shouldPulse ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if state.shouldPulse {
                    isPulsing = true
                }
            }
            .onChange(of: state) { _, newState in
                isPulsing = newState.shouldPulse
            }
    }
}

#Preview {
    HStack(spacing: 20) {
        VStack {
            StatusDot(state: .idle)
            Text("Idle").font(.caption)
        }
        VStack {
            StatusDot(state: .active)
            Text("Active").font(.caption)
        }
        VStack {
            StatusDot(state: .warning)
            Text("Warning").font(.caption)
        }
        VStack {
            StatusDot(state: .error)
            Text("Error").font(.caption)
        }
    }
    .padding()
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Components/StatusDot.swift
git commit -m "feat: simplify StatusDot with system colors"
```

---

## Task 9: Simplify SparklineView

**Files:**

- Modify: `ClaudeMonitor/Components/SparklineView.swift`

**Step 1: Keep SparklineView but use system colors**

```swift
import SwiftUI
import Charts

struct SparklineView: View {
    let data: [Double]

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            AreaMark(
                x: .value("Index", index),
                y: .value("Value", value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Index", index),
                y: .value("Value", value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.blue)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.background(.clear) }
        .chartYScale(domain: 0...8)
    }
}

extension String {
    func sparklineToData() -> [Double] {
        let chars: [Character: Double] = [
            "▁": 1, "▂": 2, "▃": 3, "▄": 4,
            "▅": 5, "▆": 6, "▇": 7, "█": 8
        ]
        return self.compactMap { chars[$0] }
    }
}

#Preview {
    VStack {
        SparklineView(data: [1, 3, 2, 5, 4, 6, 3, 2, 4, 5])
            .frame(width: 80, height: 24)

        SparklineView(data: "▁▂▃▅▇▅▃▂▁▂".sparklineToData())
            .frame(width: 80, height: 24)
    }
    .padding()
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Components/SparklineView.swift
git commit -m "feat: simplify SparklineView with system blue"
```

---

## Task 10: Update Enums to Remove Theme References

**Files:**

- Modify: `ClaudeMonitor/Models/Enums.swift`

**Step 1: Update color references in Enums.swift**

```swift
import SwiftUI

enum AgentType: String, CaseIterable, Codable, Sendable {
    case explore
    case plan
    case bash
    case general
    case codeReview
    case compact
    case promptSuggestion
    case unknown

    init(from string: String) {
        switch string.lowercased() {
        case "explore": self = .explore
        case "plan": self = .plan
        case "bash": self = .bash
        case "general", "general-purpose": self = .general
        case "codereview", "code_review", "code-review": self = .codeReview
        case "compact": self = .compact
        case "prompt_suggestion", "promptsuggestion": self = .promptSuggestion
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .explore: "Explore"
        case .plan: "Plan"
        case .bash: "Bash"
        case .general: "General"
        case .codeReview: "Code Review"
        case .compact: "Compact"
        case .promptSuggestion: "Prompt Suggestion"
        case .unknown: "Unknown"
        }
    }
}

enum AgentStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

enum TaskStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

enum LogLevel: String, CaseIterable, Codable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .error: .red
        }
    }
}

enum MenuBarStatus: Sendable {
    case idle
    case active
    case warning

    var iconName: String {
        switch self {
        case .idle: "circle"
        case .active: "circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .gray
        case .active: .blue
        case .warning: .yellow
        }
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild -scheme ClaudeMonitor build 2>&1 | grep -E '(error:|BUILD)'
```

**Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitor/Models/Enums.swift
git commit -m "feat: update Enums to use system colors"
```

---

## Task 11: Delete Remaining Unused Views

**Files:**

- Delete: `ClaudeMonitor/Views/Detail/DetailView.swift`
- Delete: `ClaudeMonitor/Views/ConflictBanner.swift`

**Step 1: Delete unused files**

```bash
rm ClaudeMonitor/ClaudeMonitor/Views/Detail/DetailView.swift
rm ClaudeMonitor/ClaudeMonitor/Views/ConflictBanner.swift
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove unused DetailView and ConflictBanner"
```

---

## Task 12: Final Build and Test

**Step 1: Clean build**

```bash
cd /Users/karelmares/Work/m29/cm-swift/ClaudeMonitor
xcodebuild clean -scheme ClaudeMonitor -quiet
xcodebuild -scheme ClaudeMonitor -configuration Debug build 2>&1 | grep -E '(error:|warning:|BUILD)'
```

Expected: BUILD SUCCEEDED

**Step 2: Run the app**

```bash
open /Users/karelmares/Library/Developer/Xcode/DerivedData/ClaudeMonitor-*/Build/Products/Debug/ClaudeMonitor.app
```

**Step 3: Manual verification checklist**

- [ ] App launches without crash
- [ ] Menu bar icon appears
- [ ] Menu bar dropdown shows instances
- [ ] Clicking instance opens main window
- [ ] Sidebar shows instances with status dots
- [ ] Selecting instance shows activity feed
- [ ] Console expands/collapses
- [ ] Works in both light and dark mode

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete native macOS redesign"
```
