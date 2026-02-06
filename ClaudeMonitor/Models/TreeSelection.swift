import Foundation

enum TreeSelection: Hashable, Sendable {
    case instance(Int)      // PID
    case agent(String)      // Agent ID
    case task(String)       // Task ID
}
