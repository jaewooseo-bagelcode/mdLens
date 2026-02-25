import SwiftUI

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var filteredFiles: [URL] {
        guard !searchText.isEmpty else { return appState.articleFiles }
        let query = searchText.lowercased()
        return appState.articleFiles.filter {
            $0.lastPathComponent.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quick Open...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        if let first = filteredFiles.first {
                            appState.openFile(url: first)
                            isPresented = false
                        }
                    }
            }
            .padding(12)

            Divider()

            if filteredFiles.isEmpty {
                Text("No matching files")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(filteredFiles, id: \.self) { url in
                    Button {
                        appState.openFile(url: url)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.body)
                            Text(url.path())
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500, height: 350)
    }
}
