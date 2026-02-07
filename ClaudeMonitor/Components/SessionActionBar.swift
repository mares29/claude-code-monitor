import SwiftUI

struct SessionActionBar: View {
    let instance: ClaudeInstance

    @State private var instanceToKill: ClaudeInstance?
    @State private var copyConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: working directory (click to copy)
            Button {
                InstanceActions.copyToClipboard(instance.workingDirectory)
                copyConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(copyConfirmation ? Color.green : Color.secondary)

                    Text(instance.workingDirectory)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .animation(.easeInOut(duration: 0.15), value: copyConfirmation)
            }
            .buttonStyle(.borderless)
            .help("Copy working directory")

            Spacer()

            // Right: action buttons
            HStack(spacing: 2) {
                if instance.terminalApp != nil {
                    actionButton(
                        icon: "terminal",
                        tooltip: "Focus Terminal",
                        action: {
                            InstanceActions.focusTerminal(
                                terminalApp: instance.terminalApp,
                                tty: instance.tty
                            )
                        }
                    )
                }

                actionButton(
                    icon: "folder",
                    tooltip: "Open in Finder",
                    action: {
                        InstanceActions.openInFinder(path: instance.workingDirectory)
                    }
                )

                if let editor = editorName {
                    actionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        tooltip: "Open in \(editor)",
                        action: {
                            InstanceActions.openInEditor(
                                path: instance.workingDirectory,
                                editor: editor
                            )
                        }
                    )
                }

                if let sessionId = instance.sessionId {
                    actionButton(
                        icon: "doc.text",
                        tooltip: "Open Session Log",
                        action: {
                            InstanceActions.openSessionLog(
                                workingDirectory: instance.workingDirectory,
                                sessionId: sessionId
                            )
                        }
                    )
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                actionButton(
                    icon: "stop.circle",
                    tooltip: "Interrupt (^C)…",
                    tint: .red,
                    action: {
                        instanceToKill = instance
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .alert(
            "Interrupt Process?",
            isPresented: Binding(
                get: { instanceToKill != nil },
                set: { if !$0 { instanceToKill = nil } }
            ),
            presenting: instanceToKill
        ) { inst in
            Button("Cancel", role: .cancel) {}
            Button("Interrupt", role: .destructive) {
                InstanceActions.interrupt(pid: inst.pid)
            }
        } message: { inst in
            let name = URL(fileURLWithPath: inst.workingDirectory).lastPathComponent
            Text("Send ^C to \(name) (PID \(inst.pid)). This will likely stop the process.")
        }
        .task(id: copyConfirmation) {
            guard copyConfirmation else { return }
            try? await Task.sleep(for: .seconds(1))
            copyConfirmation = false
        }
    }

    // MARK: - Subviews

    private func actionButton(
        icon: String,
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
        .buttonStyle(.borderless)
        .help(tooltip)
    }

    // MARK: - Computed

    private var editorName: String? {
        switch instance.terminalApp {
        case "VS Code": "VS Code"
        case "Cursor": "Cursor"
        default: nil
        }
    }
}
