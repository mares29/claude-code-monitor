import Foundation

final class SessionFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "SessionFileWatcher", qos: .utility)

    func watch(path: URL, onChange: @escaping () -> Void) {
        queue.sync {
            self._stopWatching()
        }

        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        newSource.setEventHandler {
            DispatchQueue.main.async {
                onChange()
            }
        }

        newSource.setCancelHandler {
            // FD is closed synchronously in _stopWatching(), not here.
        }

        queue.sync {
            self.fileDescriptor = fd
            self.source = newSource
        }

        newSource.resume()
    }

    func stopWatching() {
        queue.sync {
            self._stopWatching()
        }
    }

    /// Must be called on `queue`.
    private func _stopWatching() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        _stopWatching()
    }
}
