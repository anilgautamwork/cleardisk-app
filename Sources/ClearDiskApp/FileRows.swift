import Core
import SwiftUI

struct FoundFile: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool

    init(name: String, path: String, size: Int64, isDirectory: Bool) {
        self.id = path
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
    }
}

/// Walk the scanned tree collecting entries. `descend` prunes subtrees (return
/// false to skip); `matches` decides inclusion.
func collectEntries(root: FileNode, rootPath: String,
                    descend: (FileNode) -> Bool,
                    matches: (FileNode) -> Bool) -> [FoundFile] {
    var found: [FoundFile] = []
    func walk(_ node: FileNode, path: String) {
        for child in node.children ?? [] {
            let childPath = path + "/" + child.name
            if matches(child) {
                found.append(FoundFile(name: child.name, path: childPath,
                                       size: child.size, isDirectory: child.isDirectory))
            }
            if child.isDirectory && descend(child) {
                walk(child, path: childPath)
            }
        }
    }
    walk(root, path: rootPath)
    return found
}

/// Row list shared by Large Files and Search: reveal + trash with
/// confirmation, respecting the safety blocklist.
struct FileRowsView: View {
    @Environment(AppState.self) private var state
    @Binding var files: [FoundFile]
    @State private var confirmTrash: FoundFile?
    @State private var deleteRequest: DeleteForeverRequest?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(files) { file in
                    row(file)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .confirmationDialog(
            "Move \"\(confirmTrash?.name ?? "")\" (\(fmtBytes(confirmTrash?.size ?? 0))) to the Trash?",
            isPresented: .init(get: { confirmTrash != nil },
                               set: { if !$0 { confirmTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let file = confirmTrash,
                   let url = try? TrashService.trash(file.path) {
                    files.removeAll { $0.id == file.id }
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
            DeleteForeverSheet(request: request) {
                files.removeAll { $0.path == request.path }
            }
        }
    }

    private func row(_ file: FoundFile) -> some View {
        HoverRow {
        HStack(spacing: 14) {
            FileIconChip(name: file.name, isDirectory: file.isDirectory)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(abbreviateHome((file.path as NSString).deletingLastPathComponent))
                    .font(.system(size: 11.5))
                    .foregroundStyle(UI.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(fmtBytes(file.size))
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
            Button("Reveal") { revealInFinder(file.path) }
                .buttonStyle(.link)
                .font(.system(size: 12))
            let allowed = TrashService.verdict(forTrashing: file.path) == .allowed
            Button("Trash") { confirmTrash = file }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .disabled(!allowed)
                .help(allowed ? "Moves to the Trash" : "Protected location — ClearDisk won't remove this")
            Button("Delete…") {
                deleteRequest = DeleteForeverRequest(name: file.name, path: file.path, size: file.size)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .foregroundStyle(allowed ? Color(hex: 0xFF3B30) : UI.textSecondary)
            .disabled(!allowed)
            .help(allowed ? "Delete forever — frees space immediately, cannot be undone"
                  : "Protected location — ClearDisk won't remove this")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        }
    }
}

/// Bottom toast with optional Undo, driven by AppState.
struct ToastView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let toast = state.toast {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x34C759))
                Text(toast.message)
                    .font(.system(size: 13))
                    .lineLimit(2)
                if toast.undoItems != nil {
                    Button("Undo") { state.undoLastClean() }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.link)
                }
                Button {
                    state.toast = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(UI.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.cardBorder))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
