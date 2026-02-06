import Foundation

struct ProcessParser: Sendable {
    /// Known terminal app names to detect (lowercase for matching).
    /// Ordered: specific names first, generic ("terminal") last to avoid false matches
    /// on compound names like "Cursor Helper: terminal pty-host".
    private static let knownTerminals: [String] = [
        "iterm2", "iterm", "warp", "cursor", "code",
        "kitty", "alacritty", "hyper", "zed", "wezterm", "rio", "ghostty",
        "tmux", "terminal"
    ]

    /// Parse ps aux output for Claude processes
    nonisolated static func parse(psOutput: String) -> [ClaudeInstance] {
        var instances: [ClaudeInstance] = []

        let lines = psOutput.components(separatedBy: "\n")
        for line in lines {
            guard let instance = parseLine(line) else { continue }
            instances.append(instance)
        }

        return instances
    }

    private nonisolated static func parseLine(_ line: String) -> ClaudeInstance? {
        // Skip non-claude lines and helper processes
        guard line.contains("claude") else { return nil }
        guard !line.contains("Claude Helper") else { return nil }
        guard !line.contains("Claude.app/Contents/Frameworks") else { return nil }
        guard !line.contains("grep") else { return nil }

        // ps aux format: USER PID %CPU %MEM VSZ RSS TT STAT STARTED TIME COMMAND
        // Index:          0    1    2    3    4   5  6   7      8     9    10
        let components = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
        guard components.count >= 11 else { return nil }

        guard let pid = Int(components[1]) else { return nil }

        // Parse CPU% (column 2)
        let cpuPercent = Double(components[2]) ?? 0.0

        // Parse RSS in KB (column 5), convert to MB
        let rssKB = Int(components[5]) ?? 0
        let memoryMB = rssKB / 1024

        // Parse TTY (column 6) - "??" means no TTY
        let ttyRaw = String(components[6])
        let tty = ttyRaw == "??" ? nil : ttyRaw

        // Parse process start time (column 8)
        let startedStr = String(components[8])
        let startTime = parseStartTime(startedStr) ?? Date()

        // Command is everything after column 10
        let command = String(components[10])

        // Extract arguments
        let args = command.components(separatedBy: " ")
        guard !args.isEmpty else { return nil }

        // Must be claude CLI (not Claude.app main process)
        let executable = args[0]
        guard executable.contains("claude") && !executable.contains(".app") else { return nil }

        // Extract working directory from lsof or use home
        let workingDirectory = extractWorkingDirectory(pid: pid) ?? NSHomeDirectory()

        // Extract session ID from --resume argument, active debug log, or sessions-index.json
        let sessionId = ClaudeInstance.extractSessionId(from: args, workingDirectory: workingDirectory, pid: pid)

        // Detect terminal app by walking PPID chain
        let terminalApp = detectTerminalApp(pid: pid)

        // Consider active if CPU usage > 5%
        let isActive = cpuPercent > 5.0

        return ClaudeInstance(
            pid: pid,
            workingDirectory: workingDirectory,
            sessionId: sessionId,
            startTime: startTime,
            arguments: args,
            isActive: isActive,
            terminalApp: terminalApp,
            cpuPercent: cpuPercent,
            memoryMB: memoryMB,
            tty: tty
        )
    }

    /// Detect terminal app by walking up the PPID chain
    nonisolated static func detectTerminalApp(pid: Int) -> String? {
        var currentPid = pid
        var visited: Set<Int> = []

        // Walk up to 10 levels to avoid infinite loops
        for _ in 0..<10 {
            guard !visited.contains(currentPid) else { break }
            visited.insert(currentPid)

            guard let (ppid, command) = getParentProcess(pid: currentPid) else { break }

            // Check if this is a known terminal
            if let terminalName = extractTerminalName(from: command) {
                return terminalName
            }

            // Stop at init/launchd (pid 1) or if ppid is same as current
            if ppid <= 1 || ppid == currentPid { break }
            currentPid = ppid
        }

        return nil
    }

    /// Get parent PID and command for a process
    private nonisolated static func getParentProcess(pid: Int) -> (ppid: Int, command: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=,comm=", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Format: "PPID COMMAND"
            let parts = output.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let ppid = Int(parts[0]) else { return nil }

            return (ppid, String(parts[1]))
        } catch {
            return nil
        }
    }

    /// Extract terminal app name from command path
    private nonisolated static func extractTerminalName(from command: String) -> String? {
        // Get the executable name from path
        let execName = URL(fileURLWithPath: command).lastPathComponent.lowercased()

        // Check against known terminals
        for terminal in knownTerminals {
            if execName.contains(terminal) {
                return formatTerminalName(terminal)
            }
        }

        // Also check for .app in path (e.g., /Applications/Warp.app/Contents/MacOS/stable)
        if command.contains(".app") {
            // Extract app name from path like /Applications/Warp.app/Contents/...
            let components = command.components(separatedBy: "/")
            for component in components where component.hasSuffix(".app") {
                let appName = component.replacingOccurrences(of: ".app", with: "").lowercased()
                for terminal in knownTerminals {
                    if appName.contains(terminal) {
                        return formatTerminalName(terminal)
                    }
                }
            }
        }

        return nil
    }

    /// Format terminal name for display
    private nonisolated static func formatTerminalName(_ name: String) -> String {
        switch name {
        case "iterm", "iterm2": return "iTerm"
        case "terminal": return "Terminal"
        case "warp": return "Warp"
        case "cursor": return "Cursor"
        case "code": return "VS Code"
        case "kitty": return "Kitty"
        case "alacritty": return "Alacritty"
        case "hyper": return "Hyper"
        case "zed": return "Zed"
        case "wezterm": return "WezTerm"
        case "rio": return "Rio"
        case "ghostty": return "Ghostty"
        case "tmux": return "tmux"
        default: return name.capitalized
        }
    }

    /// Parse ps STARTED column which varies by age:
    /// - Today: "HH:MM" or "H:MMAM/PM"
    /// - This year: "MonDD" like "Jan15"
    /// - Previous year: "YYYY"
    private nonisolated static func parseStartTime(_ str: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // Try HH:MM format (24-hour, started today or yesterday)
        if str.contains(":") && !str.contains("AM") && !str.contains("PM") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let time = formatter.date(from: str) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
                todayComponents.hour = timeComponents.hour
                todayComponents.minute = timeComponents.minute
                if let result = calendar.date(from: todayComponents) {
                    // If result is in the future, the process started yesterday
                    if result > now {
                        return calendar.date(byAdding: .day, value: -1, to: result)
                    }
                    return result
                }
            }
        }

        // Try H:MMAM/PM format (12-hour, started today or yesterday)
        if str.uppercased().contains("AM") || str.uppercased().contains("PM") {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            formatter.amSymbol = "AM"
            formatter.pmSymbol = "PM"
            if let time = formatter.date(from: str.uppercased()) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
                todayComponents.hour = timeComponents.hour
                todayComponents.minute = timeComponents.minute
                if let result = calendar.date(from: todayComponents) {
                    // If result is in the future, the process started yesterday
                    if result > now {
                        return calendar.date(byAdding: .day, value: -1, to: result)
                    }
                    return result
                }
            }
        }

        // Try MonDD format (started this year)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMd"
        if let date = formatter.date(from: str) {
            var components = calendar.dateComponents([.month, .day], from: date)
            components.year = calendar.component(.year, from: now)
            return calendar.date(from: components)
        }

        // Try YYYY format (started previous year)
        if let year = Int(str), year > 2000 && year < 2100 {
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            return calendar.date(from: components)
        }

        return nil
    }

    private nonisolated static func extractWorkingDirectory(pid: Int) -> String? {
        // Use lsof to get current working directory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Format: p<pid>\nn<path>
            let lines = output.components(separatedBy: "\n")
            for line in lines where line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        } catch {
            // Fall through to nil
        }

        return nil
    }
}
