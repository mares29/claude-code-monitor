import SwiftUI

struct DiffSummaryView: View {
    let instance: ClaudeInstance
    let summary: GitDiffSummary

    @State private var expandedFile: String?
    @State private var fileDiffs: [String: String] = [:]

    private let scanner = GitDiffScanner()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionActionBar(instance: instance)
            Divider()

            if summary.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Working tree is clean")
                )
                .frame(maxHeight: .infinity)
            } else {
                // Stats bar
                HStack(spacing: 16) {
                    Label("\(summary.fileCount) files", systemImage: "doc")
                    Label("+\(summary.totalInsertions)", systemImage: "plus")
                        .foregroundStyle(.green)
                    Label("-\(summary.totalDeletions)", systemImage: "minus")
                        .foregroundStyle(.red)
                }
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // File list with expandable diffs
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(summary.entries) { entry in
                            fileRow(entry)
                            if expandedFile == entry.id {
                                diffContent(for: entry)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ entry: GitDiffEntry) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedFile == entry.id {
                    expandedFile = nil
                } else {
                    expandedFile = entry.id
                    loadDiff(for: entry)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expandedFile == entry.id ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                DiffFileRow(entry: entry)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func diffContent(for entry: GitDiffEntry) -> some View {
        if let diff = fileDiffs[entry.filePath], !diff.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    Text(String(line))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 16)
                        .background(lineBackground(String(line)))
                }
            }
            .padding(.bottom, 8)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.15)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.15)
        } else if line.hasPrefix("@@") {
            return Color.blue.opacity(0.1)
        }
        return .clear
    }

    private func loadDiff(for entry: GitDiffEntry) {
        guard fileDiffs[entry.filePath] == nil else { return }
        let path = entry.filePath
        let dir = instance.workingDirectory
        let sc = scanner
        Task {
            let diff = await sc.fullDiff(for: path, in: dir)
            await MainActor.run {
                fileDiffs[path] = diff
            }
        }
    }
}
