import SwiftUI

struct MainView: View {
    @Bindable var state: MonitorState
    @State private var instanceToKill: ClaudeInstance?
    @State private var copyConfirmation: String?
    @State private var expandedGroups: Set<String> = []
    @State private var knownDirectories: Set<String> = []
    @State private var detailTab: DetailTab = .session

    enum DetailTab: Hashable {
        case session
        case changes
    }

    private var selectedPid: Int? {
        if case .instance(let pid) = state.selectedItem { return pid }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) {
            if let message = copyConfirmation {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: copyConfirmation)
        .task(id: copyConfirmation) {
            guard copyConfirmation != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copyConfirmation = nil
        }
        .onChange(of: Set(state.instances.map(\.workingDirectory))) { _, currentDirs in
            // Auto-expand only genuinely new working directories
            let newDirs = currentDirs.subtracting(knownDirectories)
            expandedGroups.formUnion(newDirs)
            knownDirectories = currentDirs
        }
        .onChange(of: state.instances.map(\.pid)) { _, pids in
            // Auto-select first instance if selection is invalid
            if selectedPid == nil || !pids.contains(where: { $0 == selectedPid }) {
                state.selectedItem = state.instances.first.map { .instance($0.pid) }
            }
        }
        .alert(
            "Kill Process?",
            isPresented: Binding(
                get: { instanceToKill != nil },
                set: { if !$0 { instanceToKill = nil } }
            ),
            presenting: instanceToKill
        ) { instance in
            Button("Cancel", role: .cancel) {}
            Button("Kill", role: .destructive) {
                InstanceActions.terminate(pid: instance.pid)
            }
        } message: { instance in
            let name = URL(fileURLWithPath: instance.workingDirectory).lastPathComponent
            Text("This will terminate \(name) (PID \(instance.pid)).\n\(instance.workingDirectory)")
        }
    }

    // MARK: - Sidebar

    private var allInstances: [ClaudeInstance] {
        state.groupedInstances.flatMap(\.instances)
    }

    private var sidebar: some View {
        List {
            ForEach(state.groupedInstances) { group in
                Section(isExpanded: expandedGroupBinding(for: group.workingDirectory)) {
                    ForEach(Array(group.instances.enumerated()), id: \.element.id) { index, instance in
                        instanceRow(instance: instance, index: index, groupCount: group.instances.count)
                    }
                } header: {
                    GroupHeaderLabel(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 500)
        .onKeyPress(.upArrow) {
            selectAdjacentInstance(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectAdjacentInstance(direction: 1)
            return .handled
        }
    }

    private func selectAdjacentInstance(direction: Int) {
        let instances = allInstances
        guard !instances.isEmpty else { return }
        guard let currentIndex = instances.firstIndex(where: { $0.pid == selectedPid }) else {
            state.selectedItem = instances.first.map { .instance($0.pid) }
            return
        }
        let newIndex = min(max(currentIndex + direction, 0), instances.count - 1)
        state.selectedItem = .instance(instances[newIndex].pid)
    }

    private func instanceRow(instance: ClaudeInstance, index: Int, groupCount: Int) -> some View {
        let sid = instance.sessionId
        return HStack(spacing: 4) {
            TreeLine(isLast: index == groupCount - 1)
            InstanceRow(
                instance: instance,
                sparkline: sid.flatMap { state.sessionSparklines[$0] },
                isSelected: selectedPid == instance.pid,
                currentAction: sid.flatMap { state.sessionCurrentActions[$0] },
                currentModel: sid.flatMap { state.sessionCurrentModels[$0] },
                latestTokens: sid.flatMap { state.sessionLatestTokens[$0] }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedItem = .instance(instance.pid)
        }
        .instanceContextMenu(
            instance: instance,
            instanceToKill: $instanceToKill,
            onCopy: { message in copyConfirmation = message }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let pid = selectedPid,
           let instance = state.instances.first(where: { $0.pid == pid }) {
            VStack(spacing: 0) {
                switch detailTab {
                case .session:
                    SessionFeedView(instance: instance)
                        .frame(maxHeight: .infinity)
                case .changes:
                    DiffSummaryView(
                        instance: instance,
                        summary: state.gitDiffs[instance.workingDirectory] ?? .empty
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    let diff = state.gitDiffs[instance.workingDirectory] ?? .empty
                    Picker("", selection: $detailTab) {
                        Text("Session").tag(DetailTab.session)
                        Text(diff.fileCount > 0 ? "Changes (\(diff.fileCount))" : "Changes")
                            .tag(DetailTab.changes)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 6) {
                        // Worktree path pill
                        Button {
                            InstanceActions.copyToClipboard(instance.workingDirectory)
                            copyConfirmation = "Path copied"
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text(URL(fileURLWithPath: instance.workingDirectory).lastPathComponent)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .help(instance.workingDirectory)

                        // Action buttons pill
                        HStack(spacing: 0) {
                            if instance.terminalApp != nil {
                                toolbarIconButton("terminal", tooltip: "Focus Terminal") {
                                    InstanceActions.focusTerminal(
                                        terminalApp: instance.terminalApp,
                                        tty: instance.tty
                                    )
                                }
                            }

                            toolbarIconButton("folder", tooltip: "Open in Finder") {
                                InstanceActions.openInFinder(path: instance.workingDirectory)
                            }

                            if let editor = editorName(for: instance) {
                                toolbarIconButton("chevron.left.forwardslash.chevron.right", tooltip: "Open in \(editor)") {
                                    InstanceActions.openInEditor(
                                        path: instance.workingDirectory,
                                        editor: editor
                                    )
                                }
                            }

                            if let sessionId = instance.sessionId {
                                toolbarIconButton("doc.text", tooltip: "Open Session Log") {
                                    InstanceActions.openSessionLog(
                                        workingDirectory: instance.workingDirectory,
                                        sessionId: sessionId
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)

                        // Interrupt (standalone)
                        toolbarIconButton("stop.circle", tooltip: "Interrupt (^C)", tint: .red) {
                            InstanceActions.interrupt(pid: instance.pid)
                        }
                    }
                }
            }
        } else if let instance = state.instances.first {
            SessionFeedView(instance: instance)
                .onAppear { state.selectedItem = .instance(instance.pid) }
        } else {
            ContentUnavailableView(
                "No Instances",
                systemImage: "terminal",
                description: Text("No Claude Code instances are running")
            )
        }
    }

    private func editorName(for instance: ClaudeInstance) -> String? {
        switch instance.terminalApp {
        case "VS Code": "VS Code"
        case "Cursor": "Cursor"
        default: nil
        }
    }

    private func toolbarIconButton(
        _ icon: String,
        tooltip: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Helpers

    private func expandedGroupBinding(for directory: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(directory) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroups.insert(directory)
                } else {
                    expandedGroups.remove(directory)
                }
            }
        )
    }
}

#Preview {
    MainView(state: MonitorState())
}
