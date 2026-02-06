import Foundation

struct InstanceGroup: Identifiable {
    let workingDirectory: String
    let instances: [ClaudeInstance]

    var id: String { workingDirectory }

    var displayName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    var activeCount: Int {
        instances.filter(\.isActive).count
    }
}
