import Core
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    @State private var files: [FoundFile] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Your biggest files",
                         subtitle: "Files over 100 MB, largest first. Review before removing — these are yours.")

            if loading && files.isEmpty {
                Spacer()
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Finding your biggest files…")
                        .font(.system(size: 13))
                        .foregroundStyle(UI.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                FileRowsView(files: $files)
            }
        }
        .onAppear(perform: collect)
        .onChange(of: state.scanDate) { collect() }
        .onChange(of: state.treeVersion) { collect() }
    }

    private func collect() {
        guard let root = state.root else { return }
        loading = true
        let rootPath = state.scanPath
        Task {
            let found = await Self.collectLarge(root: root, rootPath: rootPath)
            files = found
            loading = false
        }
    }

    /// Off the main actor so the section switch stays instant on huge trees.
    private nonisolated static func collectLarge(root: FileNode, rootPath: String) async -> [FoundFile] {
        let found = collectEntries(
            root: root, rootPath: rootPath,
            descend: { $0.size >= 100_000_000 },
            matches: { !$0.isDirectory && $0.size >= 100_000_000 })
        return Array(found.sorted { $0.size > $1.size }.prefix(200))
    }
}
