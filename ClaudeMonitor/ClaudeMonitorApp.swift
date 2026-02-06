import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @State private var state = MonitorState()
    @Environment(\.openWindow) private var openWindow

    private let processScanner = ProcessScanner()
    private let logTailer = LogTailer()
    private let agentScanner = AgentScanner()

    // Activity tracking services (techniques 1-5)
    private let fileTracker = FileTracker()
    private let toolParser = ToolOperationParser()
    private let conflictDetector = ConflictDetector()
    private let activityTracker = ActivityTracker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(state: state)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))

                let activeCount = state.instances.filter(\.isActive).count
                let totalCount = state.instances.count

                if totalCount > 0 {
                    Text("\(totalCount)/\(activeCount)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Claude Monitor", id: "main") {
            MainView(state: state)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    state.isMainWindowVisible = true
                }
                .onDisappear {
                    state.isMainWindowVisible = false
                }
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                if let instance = selectedInstance {
                    Button("Interrupt") {
                        InstanceActions.interrupt(pid: instance.pid)
                    }
                    .keyboardShortcut(".", modifiers: .command)

                    if instance.terminalApp != nil {
                        Button("Focus Terminal") {
                            InstanceActions.focusTerminal(
                                terminalApp: instance.terminalApp,
                                tty: instance.tty
                            )
                        }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                    }

                    Button("Open in Finder") {
                        InstanceActions.openInFinder(path: instance.workingDirectory)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Button("Copy Working Directory") {
                        InstanceActions.copyToClipboard(instance.workingDirectory)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
        }
    }

    private var selectedInstance: ClaudeInstance? {
        guard case .instance(let pid) = state.selectedItem else { return nil }
        return state.instances.first { $0.pid == pid }
    }

    init() {
        startBackgroundServices()
        startActivityScanning()
    }

    private func startBackgroundServices() {
        let scanner = processScanner
        let tailer = logTailer
        let agentScan = agentScanner

        // Start process scanning
        Task.detached {
            for await instances in await scanner.startPolling() {
                // Scan for agents for each instance
                var instancesWithData = instances
                for i in instancesWithData.indices {
                    if let sessionId = instancesWithData[i].sessionId {
                        let agents = await agentScan.scanAgents(
                            for: sessionId,
                            projectPath: instancesWithData[i].workingDirectory
                        )
                        instancesWithData[i].agents = agents
                    }
                }
                let finalInstances = instancesWithData
                await MainActor.run {
                    state.updateInstances(finalInstances)
                }
            }
        }

        // Start log tailing
        Task.detached {
            for await entry in await tailer.startTailing() {
                await MainActor.run {
                    state.addLogEntry(entry)
                }
            }
        }
    }

    private func startActivityScanning() {
        let tracker = fileTracker
        let parser = toolParser
        let conflicts = conflictDetector
        let activity = activityTracker

        Task.detached {
            while true {
                try? await Task.sleep(for: .seconds(2))

                // Get current instances
                let instances = await MainActor.run { state.instances }

                for instance in instances {
                    guard let sessionId = instance.sessionId else { continue }

                    // Build path to session JSONL
                    let path = Self.sessionFilePath(
                        workingDirectory: instance.workingDirectory,
                        sessionId: sessionId
                    )

                    // Technique 1: Read only new lines
                    let newLines = await tracker.readNewLines(from: path)

                    // Technique 4: Parse tool operations
                    var allOps: [ToolOperation] = []
                    for line in newLines {
                        let ops = parser.parse(line: line, sessionId: sessionId)
                        allOps.append(contentsOf: ops)

                        // Technique 2: Record for conflict detection
                        for op in ops {
                            _ = await conflicts.record(op)
                        }

                        // Technique 3: Record for activity tracking
                        if !ops.isEmpty {
                            await activity.record(sessionId: sessionId, count: ops.count)
                        }
                    }

                    // Update UI with new operations
                    let opsToAdd = allOps
                    if !opsToAdd.isEmpty {
                        await MainActor.run {
                            state.addOperations(opsToAdd)
                        }
                    }

                    // Update sparkline for this session
                    let spark = await activity.sparkline(for: sessionId)

                    // Extract live data from latest JSONL entries
                    let liveData = Self.extractLiveData(from: newLines)
                    let sid = sessionId

                    await MainActor.run {
                        state.updateSparkline(sessionId: sid, sparkline: spark)
                        state.updateSessionLiveData(
                            sessionId: sid,
                            action: liveData.action,
                            model: liveData.model,
                            tokens: liveData.tokens
                        )
                    }
                }

                // Prune expired conflicts and update UI
                await conflicts.pruneExpired()
                let activeConflicts = await conflicts.activeConflicts
                await MainActor.run {
                    state.updateConflicts(activeConflicts)
                }
            }
        }
    }

    private nonisolated static func sessionFilePath(workingDirectory: String, sessionId: String) -> String {
        let encoded = workingDirectory
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "\(NSHomeDirectory())/.claude/projects/\(encoded)/\(sessionId).jsonl"
    }

    /// Extract current action, model, and tokens from raw JSONL lines
    private nonisolated static func extractLiveData(from lines: [String]) -> (action: String?, model: String?, tokens: TokenUsage?) {
        guard !lines.isEmpty else { return (nil, nil, nil) }

        let decoder = JSONDecoder()
        var latestAction: String?
        var latestModel: String?
        var latestTokens: TokenUsage?

        // Process lines in reverse to find the most recent data
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(SessionEntry.self, from: data) else {
                continue
            }

            // Extract model from assistant entries
            if latestModel == nil, entry.type == "assistant",
               let model = entry.message?.model {
                let turn = ConversationTurn(id: "", timestamp: Date(), model: model)
                latestModel = turn.displayModel
            }

            // Extract tokens from assistant entries
            if latestTokens == nil, entry.type == "assistant",
               let usage = entry.message?.usage {
                latestTokens = TokenUsage(
                    inputTokens: usage.inputTokens ?? 0,
                    outputTokens: usage.outputTokens ?? 0,
                    cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                    cacheCreationTokens: usage.cacheCreationInputTokens ?? 0
                )
            }

            // Extract current action from assistant content
            if latestAction == nil, let content = entry.message?.content {
                for item in content.reversed() {
                    if item.type == "tool_use", let name = item.name {
                        let target = item.input?["file_path"]?.stringValue
                            ?? item.input?["path"]?.stringValue
                            ?? item.input?["command"]?.stringValue.flatMap {
                                String($0.prefix(40))
                            }
                            ?? item.input?["pattern"]?.stringValue
                        latestAction = target != nil ? "\(name) \(target!)" : name
                        break
                    } else if item.type == "text", let text = item.text, !text.isEmpty {
                        latestAction = String(text.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                        break
                    }
                }
            }

            // Stop once we have everything
            if latestAction != nil && latestModel != nil && latestTokens != nil {
                break
            }
        }

        return (latestAction, latestModel, latestTokens)
    }
}
