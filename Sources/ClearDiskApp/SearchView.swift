import Core
import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var results: [FoundFile] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Search everything you scanned")
                    .font(.system(size: 26, weight: .bold))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(UI.textSecondary)
                    TextField("File or folder name…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.cardBorder))
                .frame(maxWidth: 520)
                if !query.isEmpty {
                    Text(results.isEmpty && query.count >= 2
                         ? "Nothing found for \"\(query)\""
                         : "\(results.count) result\(results.count == 1 ? "" : "s"), largest first")
                        .font(.system(size: 12.5))
                        .foregroundStyle(UI.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            FileRowsView(files: $results)
        }
        .onChange(of: query) { runSearch() }
        .onChange(of: state.scanDate) {
            results = []
            runSearch()
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let needle = query.lowercased()
        guard needle.count >= 2, let root = state.root else {
            results = []
            return
        }
        let rootPath = state.scanPath
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await Self.performSearch(root: root, rootPath: rootPath, needle: needle)
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    /// Runs off the main actor (nonisolated async) so typing stays smooth
    /// while walking a multi-million-node tree.
    private nonisolated static func performSearch(root: FileNode, rootPath: String,
                                                  needle: String) async -> [FoundFile] {
        let found = collectEntries(root: root, rootPath: rootPath,
                                   descend: { _ in !Task.isCancelled },
                                   matches: { $0.name.lowercased().contains(needle) })
            .sorted { $0.size > $1.size }
        return Array(found.prefix(300))
    }
}
