import SwiftUI

struct AnnouncementMarkdownView: View {
    let text: String

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(AnnouncementMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let value):
                    inline(value).font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : .headline)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph(let value): inline(value).lineSpacing(5)
                case .listItem(let marker, let value):
                    HStack(alignment: .top, spacing: 10) { Text(marker); inline(value).frame(maxWidth: .infinity, alignment: .leading) }
                case .quote(let value):
                    HStack(spacing: 12) {
                        Rectangle().fill(.blue.opacity(0.5)).frame(width: 3)
                        inline(value).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: true)
                case .code(let value):
                    ScrollView(.horizontal) {
                        Text(value).font(.system(.callout, design: .monospaced)).padding(14)
                    }.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                case .divider: Divider()
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
