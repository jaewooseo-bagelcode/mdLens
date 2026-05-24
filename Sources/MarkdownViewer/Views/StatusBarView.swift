import SwiftUI

struct StatusBarView: View {
    let stats: DocumentStats
    let fileURL: URL?

    var body: some View {
        HStack(spacing: 16) {
            Text("\(stats.wordCount) words")
            Text("\(stats.charCount) chars")
            Text("\(stats.lineCount) lines")
            Text("~\(stats.readingTimeMinutes) min read")

            Spacer()

            if let fileURL {
                Text(fileURL.path())
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
