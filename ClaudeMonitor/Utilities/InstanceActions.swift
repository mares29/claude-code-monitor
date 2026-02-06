import AppKit
import Foundation

struct InstanceActions: Sendable {

    // MARK: - Process Control

    /// Send SIGINT (equivalent to Ctrl+C)
    nonisolated static func interrupt(pid: Int) {
        kill(pid_t(pid), SIGINT)
    }

    /// Send SIGTERM, then SIGKILL after 3 seconds if still alive
    nonisolated static func terminate(pid: Int) {
        kill(pid_t(pid), SIGTERM)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            // Check if process is still alive (kill with signal 0 tests existence)
            if kill(pid_t(pid), 0) == 0 {
                kill(pid_t(pid), SIGKILL)
            }
        }
    }

    // MARK: - Focus Terminal

    /// Bring the terminal window/tab containing this instance to front
    @MainActor
    static func focusTerminal(terminalApp: String?, tty: String?) {
        guard let terminalApp else { return }

        switch terminalApp {
        case "Terminal":
            focusTerminalApp(tty: tty)
        case "iTerm":
            focusiTerm(tty: tty)
        default:
            focusAppByName(terminalApp)
        }
    }

    /// Terminal.app — iterate windows/tabs to find matching tty
    @MainActor
    private static func focusTerminalApp(tty: String?) {
        guard let tty else {
            focusAppByName("Terminal")
            return
        }

        let script = """
        tell application "Terminal"
            activate
            set targetTTY to "/dev/\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTTY then
                        set selected tab of w to t
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """

        runAppleScript(script)
    }

    /// iTerm2 — iterate windows/tabs/sessions to find matching tty
    @MainActor
    private static func focusiTerm(tty: String?) {
        guard let tty else {
            focusAppByName("iTerm2")
            return
        }

        let script = """
        tell application "iTerm2"
            activate
            set targetTTY to "/dev/\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is targetTTY then
                            select t
                            select s
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        runAppleScript(script)
    }

    /// Fallback: activate app by name (no tab targeting)
    @MainActor
    private static func focusAppByName(_ name: String) {
        let appName: String
        switch name {
        case "VS Code": appName = "Visual Studio Code"
        case "iTerm": appName = "iTerm2"
        default: appName = name
        }

        let script = "tell application \"\(appName)\" to activate"
        runAppleScript(script)
    }

    @MainActor
    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    // MARK: - Utilities

    /// Reveal working directory in Finder
    @MainActor
    static func openInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Copy text to system clipboard
    @MainActor
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Open the session JSONL log file
    @MainActor
    static func openSessionLog(workingDirectory: String, sessionId: String) {
        let projectsPath = ClaudeInstance.projectsPath(for: workingDirectory)
        let logPath = "\(projectsPath)/\(sessionId).jsonl"
        let url = URL(fileURLWithPath: logPath)

        guard FileManager.default.fileExists(atPath: logPath) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open path in an editor (VS Code or Cursor)
    @MainActor
    static func openInEditor(path: String, editor: String) {
        let bundleId: String
        switch editor {
        case "Cursor": bundleId = "com.todesktop.230313mzl4w4u92"
        case "VS Code": bundleId = "com.microsoft.VSCode"
        default: return
        }

        let folderURL = URL(fileURLWithPath: path)
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId
        ) else { return }

        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
