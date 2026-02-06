import SwiftUI

struct TreeLine: View {
    let isLast: Bool

    private let lineWidth: CGFloat = 1
    private let branchWidth: CGFloat = 10
    private let color = Color.secondary.opacity(0.3)

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = size.height / 2

            // Vertical line: full height for non-last, top-to-center for last
            var vLine = Path()
            vLine.move(to: CGPoint(x: midX, y: 0))
            vLine.addLine(to: CGPoint(x: midX, y: isLast ? midY : size.height))
            context.stroke(vLine, with: .color(color), lineWidth: lineWidth)

            // Horizontal branch from center to right
            var hLine = Path()
            hLine.move(to: CGPoint(x: midX, y: midY))
            hLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(hLine, with: .color(color), lineWidth: lineWidth)
        }
        .frame(width: branchWidth)
    }
}
