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
            // Action bar - pinned at top
            SessionActionBar(instance: instance)

            Divider()

            // Timeline feed
            if turns.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Waiting for conversation data...")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(turns) { turn in
                            turnTimeline(turn)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .animation(.easeInOut(duration: 0.25), value: turns.count)
                }
            }
        }
        .task(id: instance.pid) {
            watcher.stopWatching()

            guard let sessionId = instance.sessionId else {
                turns = []
                fileOffset = 0
                return
            }

            let sessionPath = sessionFilePath(sessionId: sessionId)
            guard FileManager.default.fileExists(atPath: sessionPath.path) else {
                turns = []
                fileOffset = 0
                return
            }

            let (newTurns, newOffset) = parser.parseIncremental(sessionPath: sessionPath, fromOffset: 0)

            turns = newTurns
            expandedTextTurns = []
            expandedToolIds = []
            expandedAgentIds = []
            fileOffset = newOffset

            startWatching()
        }
        .onDisappear {
            watcher.stopWatching()
        }
    }

    // MARK: - Timeline Rendering

    @ViewBuilder
    private func turnTimeline(_ turn: ConversationTurn) -> some View {
        // User turn → blue divider
        if turn.role == .user {
            UserMessageDivider(
                text: turn.text ?? "...",
                timestamp: turn.timestamp
            )
        }

        // Assistant text → collapsible block
        if turn.role == .assistant, let text = turn.text, !text.isEmpty {
            AssistantTextBlock(
                text: text,
                timestamp: turn.timestamp,
                isExpanded: textBinding(for: turn.id)
            )
        }

        // Tool calls → individual timeline rows
        if !turn.toolCalls.isEmpty {
            ForEach(turn.toolCalls) { tool in
                TimelineRow(
                    toolCall: tool,
                    isExpanded: expandedToolIds.contains(tool.id),
                    onToggle: { toggleTool(tool.id) }
                )
            }
        }

        // Agent spawns → keep AgentBlock as-is
        if !turn.agentSpawns.isEmpty {
            ForEach(turn.agentSpawns) { agent in
                AgentBlock(
                    agent: agent,
                    isExpanded: expandedAgentIds.contains(agent.id),
                    onToggle: { toggleAgent(agent.id) }
                )
            }
        }
    }

    // MARK: - Helpers

    private func textBinding(for turnId: String) -> Binding<Bool> {
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

    private func startWatching() {
        guard let sessionId = instance.sessionId else { return }
        let sessionPath = sessionFilePath(sessionId: sessionId)

        watcher.watch(path: sessionPath) { [self] in
            Task {
                let (newTurns, newOffset) = parser.parseIncremental(sessionPath: sessionPath, fromOffset: fileOffset)
                await MainActor.run {
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
