import SwiftUI

struct DiffFileRow: View {
    let entry: GitDiffEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.status.rawValue)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 14, alignment: .center)

            Text(entry.filePath)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if entry.insertions > 0 {
                Text("+\(entry.insertions)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)
            }
            if entry.deletions > 0 {
                Text("-\(entry.deletions)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .added: return .green
        case .deleted: return .red
        case .modified: return .yellow
        case .renamed: return .blue
        case .unknown: return .secondary
        }
    }
}
