import SwiftUI

struct MainView: View {
    @Bindable var state: MonitorState
    @State private var instanceToKill: ClaudeInstance?
    @State private var copyConfirmation: String?
    @State private var expandedGroups: Set<String> = []
    @State private var knownDirectories: Set<String> = []

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
        .onChange(of: state.instances) { _, newInstances in
            // Auto-expand only genuinely new working directories
            let currentDirs = Set(newInstances.map(\.workingDirectory))
            let newDirs = currentDirs.subtracting(knownDirectories)
            expandedGroups.formUnion(newDirs)
            knownDirectories = currentDirs

            // Auto-select first instance if selection is invalid
            if selectedPid == nil || !newInstances.contains(where: { $0.pid == selectedPid }) {
                state.selectedItem = newInstances.first.map { .instance($0.pid) }
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

    private var sidebar: some View {
        List(selection: Binding(
            get: { selectedPid },
            set: { state.selectedItem = $0.map { .instance($0) } }
        )) {
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
        .tag(instance.pid)
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
            SessionFeedView(instance: instance)
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
