import SwiftUI

struct EmptyStateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Document Open")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Open a Markdown file to get started")
                .font(.body)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button("Open File...") {
                    appState.isFileImporterPresented = true
                }
                .keyboardShortcut("o")

                Button("Open Folder...") {
                    appState.isFolderImporterPresented = true
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }
}
