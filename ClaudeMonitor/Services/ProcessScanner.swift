import Foundation

actor ProcessScanner {
    private let pollInterval: Duration = .seconds(2)

    func scan() async throws -> [ClaudeInstance] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["aux"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return ProcessParser.parse(psOutput: output)
    }

    func startPolling() -> AsyncStream<[ClaudeInstance]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let instances = try await scan()
                        continuation.yield(instances)
                    } catch {
                        // Continue polling even on error
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
