import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            if let stats = appState.stats {
                Text("\(stats.wordCount) words")
                Text("\(stats.charCount) chars")
                Text("\(stats.lineCount) lines")
                Text("~\(stats.readingTimeMinutes) min read")
            }

            Spacer()

            if let doc = appState.currentDocument {
                Text(doc.url.path())
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
