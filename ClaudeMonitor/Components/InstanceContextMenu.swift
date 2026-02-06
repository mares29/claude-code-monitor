import SwiftUI

struct InstanceContextMenu: ViewModifier {
    let instance: ClaudeInstance
    @Binding var instanceToKill: ClaudeInstance?
    var onCopy: (String) -> Void = { _ in }

    func body(content: Content) -> some View {
        content.contextMenu {
            // Process control
            Button {
                InstanceActions.interrupt(pid: instance.pid)
            } label: {
                Label("Interrupt (⌃C)", systemImage: "stop.circle")
            }

            Button(role: .destructive) {
                instanceToKill = instance
            } label: {
                Label("Kill Process…", systemImage: "xmark.octagon")
            }

            Divider()

            // Focus terminal (only if available)
            if instance.terminalApp != nil {
                Button {
                    InstanceActions.focusTerminal(
                        terminalApp: instance.terminalApp,
                        tty: instance.tty
                    )
                } label: {
                    Label("Focus Terminal", systemImage: "terminal")
                }

                Divider()
            }

            // File system
            Button {
                InstanceActions.openInFinder(path: instance.workingDirectory)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            if let editor = editorName {
                Button {
                    InstanceActions.openInEditor(
                        path: instance.workingDirectory,
                        editor: editor
                    )
                } label: {
                    Label("Open in \(editor)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Divider()

            // Clipboard
            Button {
                InstanceActions.copyToClipboard(instance.workingDirectory)
                onCopy("Path copied")
            } label: {
                Label("Copy Working Directory", systemImage: "doc.on.doc")
            }

            Button {
                InstanceActions.copyToClipboard("\(instance.pid)")
                onCopy("PID copied")
            } label: {
                Label("Copy PID", systemImage: "number")
            }

            if let sessionId = instance.sessionId {
                Button {
                    InstanceActions.copyToClipboard(sessionId)
                    onCopy("Session ID copied")
                } label: {
                    Label("Copy Session ID", systemImage: "key")
                }
            }

            // Session log
            if let sessionId = instance.sessionId {
                Divider()

                Button {
                    InstanceActions.openSessionLog(
                        workingDirectory: instance.workingDirectory,
                        sessionId: sessionId
                    )
                } label: {
                    Label("Open Session Log", systemImage: "doc.text")
                }
            }
        }
    }

    /// Map terminal app to editor name for "Open in <editor>" item
    private var editorName: String? {
        switch instance.terminalApp {
        case "VS Code": return "VS Code"
        case "Cursor": return "Cursor"
        default: return nil
        }
    }
}

extension View {
    func instanceContextMenu(
        instance: ClaudeInstance,
        instanceToKill: Binding<ClaudeInstance?>,
        onCopy: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(InstanceContextMenu(instance: instance, instanceToKill: instanceToKill, onCopy: onCopy))
    }
}
