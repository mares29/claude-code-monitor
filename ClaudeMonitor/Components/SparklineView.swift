import SwiftUI

struct SparklineShape: Shape {
    let data: [Double]

    func path(in rect: CGRect) -> Path {
        guard data.count >= 2 else {
            return Path { path in
                path.move(to: CGPoint(x: 0, y: rect.height))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            }
        }

        let maxVal = max(data.max() ?? 1, 4) // Floor of 4 prevents flat lines
        let stepX = rect.width / CGFloat(data.count - 1)

        let points = data.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * stepX,
                y: rect.height - (CGFloat(value) / CGFloat(maxVal)) * rect.height
            )
        }

        return Path { path in
            path.move(to: points[0])

            // Catmull-Rom spline interpolation
            for i in 0..<points.count {
                let p0 = points[max(0, i - 1)]
                let p1 = points[i]
                let p2 = points[min(points.count - 1, i + 1)]
                let p3 = points[min(points.count - 1, i + 2)]

                if i == 0 {
                    path.move(to: p1)
                    continue
                }

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )

                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }
}

struct SparklineView: View {
    let data: [Double]
    var tint: Color = .blue

    var body: some View {
        SparklineShape(data: data)
            .stroke(
                LinearGradient(
                    colors: [tint.opacity(0.3), tint],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
    }
}

extension String {
    func sparklineToData() -> [Double] {
        let chars: [Character: Double] = [
            "▁": 1, "▂": 2, "▃": 3, "▄": 4,
            "▅": 5, "▆": 6, "▇": 7, "█": 8
        ]
        return self.compactMap { chars[$0] }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Active session
        SparklineView(data: [1, 3, 2, 5, 4, 6, 3, 2, 4, 5])
            .frame(width: 60, height: 16)

        // From unicode string
        SparklineView(data: "▁▂▃▅▇▅▃▂▁▂".sparklineToData())
            .frame(width: 60, height: 16)

        // Low activity
        SparklineView(data: [0, 1, 0, 0, 1, 0, 0, 0, 1, 0])
            .frame(width: 60, height: 16)

        // Empty/idle
        SparklineView(data: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            .frame(width: 60, height: 16)

        // Menu bar size
        SparklineView(data: "▁▂▃▅▇▅▃▂▁▂".sparklineToData())
            .frame(width: 48, height: 12)
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
