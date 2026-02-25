import SwiftUI

struct OutlineView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.outline.isEmpty {
            ContentUnavailableView {
                Label("No Outline", systemImage: "list.bullet.indent")
            } description: {
                Text("Open a document to see its outline")
            }
        } else {
            List(appState.outline) { item in
                Button {
                    appState.scrollToHeading(item.id)
                } label: {
                    Text(item.title)
                        .font(fontForLevel(item.level))
                        .foregroundStyle(item.level == 1 ? .primary : .secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(item.indentLevel) * 12)
            }
            .listStyle(.sidebar)
        }
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .headline
        case 2: return .subheadline
        default: return .body
        }
    }
}
