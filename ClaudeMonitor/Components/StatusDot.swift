import SwiftUI

enum StatusDotState {
    case idle
    case active
    case warning
    case error

    var color: Color {
        switch self {
        case .idle: .gray
        case .active: .blue
        case .warning: .yellow
        case .error: .red
        }
    }

    var iconName: String {
        switch self {
        case .idle: "circle"
        case .active: "waveform"
        case .warning: "exclamationmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }
}

struct StatusDot: View {
    let state: StatusDotState
    let size: CGFloat
    var tint: Color?

    init(state: StatusDotState, size: CGFloat = 10, tint: Color? = nil) {
        self.state = state
        self.size = size
        self.tint = tint
    }

    var body: some View {
        Image(systemName: state.iconName)
            .font(.system(size: size))
            .foregroundStyle(tint ?? state.color)
            .symbolEffect(.variableColor.iterative.reversing, isActive: state == .active)
    }
}

#Preview {
    HStack(spacing: 20) {
        VStack {
            StatusDot(state: .idle)
            Text("Idle").font(.caption)
        }
        VStack {
            StatusDot(state: .active)
            Text("Active").font(.caption)
        }
        VStack {
            StatusDot(state: .warning)
            Text("Warning").font(.caption)
        }
        VStack {
            StatusDot(state: .error)
            Text("Error").font(.caption)
        }
    }
    .padding()
}
