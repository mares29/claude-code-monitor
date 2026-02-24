import SwiftUI

/// Renders markdown text with block-level support (headings, code blocks, lists, blockquotes).
/// Uses native `AttributedString(markdown:)` with `PresentationIntent` for zero dependencies.
struct MarkdownText: View {
    let text: String
    let font: Font

    init(_ text: String, font: Font = .caption) {
        self.text = text
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Model

    private enum Block {
        case paragraph(AttributedString)
        case heading(Int, AttributedString)
        case codeBlock(String, String?) // code, language
        case bulletList([AttributedString])
        case orderedList([AttributedString])
        case blockQuote(AttributedString)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(content)
                .font(headingFont(level))
                .fontWeight(.semibold)

        case .paragraph(let content):
            Text(content)
                .font(font)
                .textSelection(.enabled)

        case .codeBlock(let code, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(font == .caption ? .caption : .body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .font(font)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(font)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 4)

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).")
                            .font(font)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(item)
                            .font(font)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 4)

        case .blockQuote(let content):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2)
                Text(content)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 8)
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: font == .caption ? .callout.weight(.bold) : .title2.weight(.bold)
        case 2: font == .caption ? .caption.weight(.bold) : .title3.weight(.bold)
        default: font == .caption ? .caption.weight(.semibold) : .headline
        }
    }

    // MARK: - Parsing

    private var blocks: [Block] {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let parsed = try? AttributedString(markdown: text, options: opts) else {
            return [.paragraph(AttributedString(text))]
        }

        var result: [Block] = []
        // Group runs by their block identity
        // Collect blocks by grouping runs with the same block identity
        var currentBlockId: Int?
        var blockStart: AttributedString.Index?
        var blockEnd: AttributedString.Index?
        var blockIntent: PresentationIntent?

        for run in parsed.runs {
            let id = run.presentationIntent?.components.first?.identity
            if id != currentBlockId {
                // Flush previous block
                if let start = blockStart, let end = blockEnd {
                    if let block = buildBlock(range: start..<end, intent: blockIntent, in: parsed) {
                        result.append(block)
                    }
                }
                currentBlockId = id
                blockStart = run.range.lowerBound
                blockIntent = run.presentationIntent
            }
            blockEnd = run.range.upperBound
        }
        // Flush last block
        if let start = blockStart, let end = blockEnd {
            if let block = buildBlock(range: start..<end, intent: blockIntent, in: parsed) {
                result.append(block)
            }
        }

        // Merge consecutive list items
        return mergeListItems(result)
    }

    private func buildBlock(
        range: Range<AttributedString.Index>,
        intent: PresentationIntent?,
        in source: AttributedString
    ) -> Block? {
        let components = intent?.components ?? []
        let content = AttributedString(source[range])

        // Check for block-level kinds
        for component in components {
            switch component.kind {
            case .codeBlock(let lang):
                let plainText = String(source.characters[range])
                return .codeBlock(plainText, lang)
            case .header(let level):
                return .heading(level, content)
            case .blockQuote:
                return .blockQuote(content)
            case .listItem:
                // Determine list type from sibling components
                let isOrdered = components.contains { $0.kind == .orderedList }
                if isOrdered {
                    return .orderedList([content])
                } else {
                    return .bulletList([content])
                }
            default:
                continue
            }
        }

        // Default: paragraph
        let plainText = String(source.characters[range])
        let trimmed = plainText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return .paragraph(content)
    }

    /// Merge consecutive bullet/ordered list items into single list blocks
    private func mergeListItems(_ blocks: [Block]) -> [Block] {
        var merged: [Block] = []
        for block in blocks {
            switch block {
            case .bulletList(let items):
                if case .bulletList(let existing) = merged.last {
                    merged[merged.count - 1] = .bulletList(existing + items)
                } else {
                    merged.append(block)
                }
            case .orderedList(let items):
                if case .orderedList(let existing) = merged.last {
                    merged[merged.count - 1] = .orderedList(existing + items)
                } else {
                    merged.append(block)
                }
            default:
                merged.append(block)
            }
        }
        return merged
    }
}
