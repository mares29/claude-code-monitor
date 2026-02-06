import Foundation

final class SessionFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "SessionFileWatcher", qos: .utility)

    func watch(path: URL, onChange: @escaping () -> Void) {
        stopWatching()

        fileDescriptor = open(path.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )

        source?.setEventHandler {
            DispatchQueue.main.async {
                onChange()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    deinit {
        stopWatching()
    }
}
