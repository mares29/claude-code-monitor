import SwiftUI

/// Handles Dock icon click to reopen the main window
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindow: OpenWindowAction?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow?(id: "main")
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure window comes to front when app is activated via Dock
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    private let gitDiffScanner = GitDiffScanner()

    var body: some Scene {
        let _ = updateDelegate()

        MenuBarExtra {
            MenuBarMenu(state: state)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))

                let activeCount = state.instances.filter(\.isActive).count

                if activeCount > 0 {
                    Text("\(activeCount)")
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

    private func updateDelegate() {
        appDelegate.openWindow = openWindow
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

        // Fast loop (0.5s): sparkline + live data (cheap file reads only)
        Task.detached {
            while true {
                try? await Task.sleep(for: .milliseconds(500))

                let instances = await MainActor.run { state.instances }

                for instance in instances {
                    guard let sessionId = instance.sessionId else { continue }

                    let path = Self.sessionFilePath(
                        workingDirectory: instance.workingDirectory,
                        sessionId: sessionId
                    )

                    let newLines = await tracker.readNewLines(from: path)

                    if !newLines.isEmpty {
                        await activity.record(sessionId: sessionId, count: newLines.count)

                        let liveData = Self.extractLiveData(from: newLines)
                        let sid = sessionId

                        // Parse tool operations inline
                        var allOps: [ToolOperation] = []
                        for line in newLines {
                            let ops = parser.parse(line: line, sessionId: sessionId)
                            allOps.append(contentsOf: ops)
                            for op in ops {
                                _ = await conflicts.record(op)
                            }
                        }

                        let opsToAdd = allOps
                        await MainActor.run {
                            if !opsToAdd.isEmpty {
                                state.addOperations(opsToAdd)
                            }
                            state.updateSessionLiveData(
                                sessionId: sid,
                                action: liveData.action,
                                model: liveData.model,
                                tokens: liveData.tokens
                            )
                        }
                    }

                    // Always update sparkline (shows decay even without new data)
                    let spark = await activity.sparkline(for: sessionId)
                    let sid = sessionId
                    await MainActor.run {
                        state.updateSparkline(sessionId: sid, sparkline: spark)
                    }
                }
            }
        }

        // Slow loop (3s): git diff scanning + conflict pruning
        Task.detached {
            while true {
                try? await Task.sleep(for: .seconds(3))

                let instances = await MainActor.run { state.instances }

                // Git diff scanning
                let directories = Array(Set(instances.map(\.workingDirectory)))
                let gitScanner = self.gitDiffScanner
                let diffs = await gitScanner.scan(workingDirectories: directories)
                await MainActor.run {
                    state.updateGitDiffs(diffs)
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
