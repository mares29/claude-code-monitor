import Foundation

actor LogTailer {
    private let debugDirectory: URL
    private var fileHandles: [String: FileHandle] = [:]
    private var fileOffsets: [String: UInt64] = [:]

    init() {
        self.debugDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/debug")
    }

    func startTailing() -> AsyncStream<LogEntry> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await tailAllFiles(continuation: continuation)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task {
                    await self?.closeAllHandles()
                }
            }
        }
    }

    private func tailAllFiles(continuation: AsyncStream<LogEntry>.Continuation) {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(
            at: debugDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let logFiles = files.filter { $0.pathExtension == "txt" }

        for file in logFiles {
            let sessionId = file.deletingPathExtension().lastPathComponent
            readNewLines(from: file, sessionId: sessionId, continuation: continuation)
        }
    }

    private func readNewLines(from url: URL, sessionId: String, continuation: AsyncStream<LogEntry>.Continuation) {
        let path = url.path

        // Get or create file handle
        let handle: FileHandle
        if let existing = fileHandles[path] {
            handle = existing
        } else {
            guard let newHandle = FileHandle(forReadingAtPath: path) else { return }
            fileHandles[path] = newHandle

            // Start from end for new files
            let offset = fileOffsets[path] ?? (try? newHandle.seekToEnd()) ?? 0
            fileOffsets[path] = offset
            handle = newHandle
        }

        // Read new data
        guard let data = try? handle.readToEnd(),
              !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        // Update offset
        fileOffsets[path] = (try? handle.offset()) ?? fileOffsets[path] ?? 0

        // Parse lines
        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            if let entry = LogParser.parse(line: line, sessionId: sessionId) {
                continuation.yield(entry)
            }
        }
    }

    private func closeAllHandles() {
        for handle in fileHandles.values {
            try? handle.close()
        }
        fileHandles.removeAll()
    }
}
