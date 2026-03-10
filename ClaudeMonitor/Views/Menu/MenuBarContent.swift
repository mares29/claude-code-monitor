import SwiftUI

struct MenuBarMenu: View {
    @Bindable var state: MonitorState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Monitor") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Divider()

        if state.instances.isEmpty {
            Text("No instances running")
        } else {
            ForEach(state.groupedInstances) { group in
                Section(groupHeader(group)) {
                    ForEach(group.instances) { instance in
                        instanceButton(instance)
                    }
                }
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func instanceButton(_ instance: ClaudeInstance) -> some View {
        let button = Button {
            state.selectedItem = .instance(instance.pid)
            openWindow(id: "main")
            NSApp.activate()
        } label: {
            Text(attributedInstanceText(instance))
        }
        if let key = shortcutKey(for: instance) {
            button.keyboardShortcut(key, modifiers: .command)
        } else {
            button
        }
    }

    private func groupHeader(_ group: InstanceGroup) -> String {
        group.displayName
    }

    private func attributedInstanceText(_ instance: ClaudeInstance) -> AttributedString {
        let plain = instanceText(instance)
        var attr = AttributedString(plain)
        if !instance.isActive {
            attr.foregroundColor = .secondary
        }
        return attr
    }

    private func instanceText(_ instance: ClaudeInstance) -> String {
        var parts: [String] = []
        if let terminal = instance.terminalApp {
            parts.append(terminal)
        }
        if instance.isDangerousMode {
            parts.append("\u{26A1}")
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " \u{b7} ")
    }

    private func shortcutKey(for instance: ClaudeInstance) -> KeyEquivalent? {
        guard let index = state.instances.firstIndex(where: { $0.id == instance.id }),
              index < 9 else {
            return nil
        }
        return KeyEquivalent(Character("\(index + 1)"))
    }
}
