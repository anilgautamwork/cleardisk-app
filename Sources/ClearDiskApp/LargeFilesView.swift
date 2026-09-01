import Core
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    @State private var files: [FoundFile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Your biggest files",
                         subtitle: "Files over 100 MB, largest first. Review before removing — these are yours.")

            FileRowsView(files: $files)
        }
        .onAppear(perform: collect)
        .onChange(of: state.scanDate) { collect() }
    }

    private func collect() {
        guard let root = state.root else { return }
        let found = collectEntries(
            root: root, rootPath: state.scanPath,
            descend: { $0.size >= 100_000_000 },
            matches: { !$0.isDirectory && $0.size >= 100_000_000 })
        files = Array(found.sorted { $0.size > $1.size }.prefix(200))
    }
}
