import Core
import SwiftUI

/// In-app folder review: every level shows its contents sorted by size with
/// proportion bars, so the biggest thing is always at the top. Click a folder
/// to descend; trash or delete right here — no Finder required.
struct BrowserView: View {
    @Environment(AppState.self) private var state
    @State private var stack: [FileNode] = []
    @State private var rows: [FileNode] = []
    @State private var confirmTrash: FoundFile?
    @State private var deleteRequest: DeleteForeverRequest?

    private var current: FileNode? { stack.last }

    private var currentPath: String {
        let base = state.scanPath == "/" ? "" : state.scanPath
        return base + stack.dropFirst().map { "/" + $0.name }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar

            if let current {
                HStack(spacing: 8) {
                    Text("\(fmtBytes(current.size)) · \((current.children?.count ?? 0).formatted()) items, biggest first")
                        .font(.system(size: 12.5))
                        .foregroundStyle(UI.textSecondary)
                    Spacer()
                    Button("Show in Finder") { revealInFinder(currentPath.isEmpty ? "/" : currentPath) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(rows.enumerated()), id: \.element.name) { index, child in
                            row(child, rank: index)
                        }
                        if let total = current.children?.count, total > rows.count {
                            Text("+ \((total - rows.count).formatted()) smaller items not shown")
                                .font(.system(size: 12))
                                .foregroundStyle(UI.textSecondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .id(state.treeVersion)
            } else {
                Spacer()
                Text("Run a scan first.")
                    .foregroundStyle(UI.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .onAppear { resolveEntry() }
        .onChange(of: state.browsePath) { resolveEntry() }
        .onChange(of: state.scanDate) { resolveEntry() }
        .onChange(of: state.treeVersion) {
            validateStack()
            refreshRows()
        }
        .confirmationDialog(
            "Move \"\(confirmTrash?.name ?? "")\" (\(fmtBytes(confirmTrash?.size ?? 0))) to the Trash?",
            isPresented: .init(get: { confirmTrash != nil },
                               set: { if !$0 { confirmTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let file = confirmTrash, let url = try? TrashService.trash(file.path) {
                    state.applyRemoval(paths: [file.path], movedToTrash: true)
                    state.showToast("Moved \(file.name) (\(fmtBytes(file.size))) to the Trash.",
                                    undo: [TrashService.TrashedItem(originalPath: file.path, trashURL: url)])
                }
                confirmTrash = nil
            }
            Button("Cancel", role: .cancel) { confirmTrash = nil }
        } message: {
            Text("You can put it back from the Trash anytime.")
        }
        .sheet(item: $deleteRequest) { request in
            DeleteForeverSheet(request: request) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                if stack.count > 1 { stack.removeLast() }
                refreshRows()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(stack.count <= 1)
            .keyboardShortcut(.upArrow, modifiers: .command)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(stack.enumerated()), id: \.offset) { index, node in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(UI.textSecondary)
                            }
                            Button {
                                stack = Array(stack.prefix(index + 1))
                                refreshRows()
                            } label: {
                                Text(index == 0 ? abbreviateHome(state.scanPath) : node.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(UI.elevated, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onChange(of: stack.count) {
                    withAnimation { proxy.scrollTo(stack.count - 1, anchor: .trailing) }
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func row(_ child: FileNode, rank: Int) -> some View {
        let childPath = currentPath + "/" + child.name
        let isBundle = BrowserView.isBundle(child.name)
        let descendable = child.isDirectory && !isBundle && !(child.children ?? []).isEmpty
        let allowed = TrashService.verdict(forTrashing: childPath) == .allowed
        let biggest = rows.first?.size ?? 1

        return HoverRow {
            HStack(spacing: 14) {
                FileIconChip(name: child.name, isDirectory: child.isDirectory)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(plainDescription(name: child.name, isDirectory: child.isDirectory,
                                          childCount: child.children?.count ?? 0))
                        .font(.system(size: 11.5))
                        .foregroundStyle(UI.textSecondary)
                        .lineLimit(1)
                }
                Spacer()

                // Share-of-biggest bar: instantly shows what dominates here.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(UI.elevated)
                        Capsule().fill(UI.accent.opacity(0.75))
                            .frame(width: max(3, geo.size.width * CGFloat(child.size) / CGFloat(max(1, biggest))))
                    }
                }
                .frame(width: 74, height: 6)

                Text(fmtBytes(child.size))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)

                Button("Trash") { confirmTrash = FoundFile(name: child.name, path: childPath,
                                                           size: child.size, isDirectory: child.isDirectory) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(!allowed)
                Button("Delete…") { deleteRequest = DeleteForeverRequest(name: child.name,
                                                                         path: childPath, size: child.size) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .foregroundStyle(allowed ? Color(hex: 0xFF3B30) : UI.textSecondary)
                    .disabled(!allowed)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(descendable ? UI.textSecondary : .clear)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if descendable {
                    stack.append(child)
                    refreshRows()
                } else {
                    revealInFinder(childPath)
                }
            }
        }
    }

    // MARK: - state

    private func resolveEntry() {
        guard let root = state.root else {
            stack = []
            rows = []
            return
        }
        if let path = state.browsePath,
           let chain = TreeSurgery.chain(for: path, root: root, scanPath: state.scanPath) {
            stack = chain
        } else if stack.isEmpty {
            stack = [root]
        }
        refreshRows()
    }

    private func validateStack() {
        guard let root = state.root else { return }
        var valid: [FileNode] = [root]
        for node in stack.dropFirst() {
            guard let children = valid.last?.children, children.contains(where: { $0 === node }) else { break }
            valid.append(node)
        }
        stack = valid
    }

    private func refreshRows() {
        rows = Array((current?.children ?? [])
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(400))
    }

    private static let bundleSuffixes = [".app", ".photoslibrary", ".imovielibrary",
                                         ".fcpbundle", ".framework", ".bundle", ".xcodeproj"]

    static func isBundle(_ name: String) -> Bool {
        bundleSuffixes.contains { name.hasSuffix($0) }
    }
}
