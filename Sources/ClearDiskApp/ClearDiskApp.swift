import Core
import SwiftUI

@main
struct ClearDiskApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("ClearDisk") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
@Observable
final class AppState {
    enum Phase {
        case welcome
        case scanning
        case done
    }

    enum Section: String, CaseIterable, Identifiable {
        case systemData = "System Data"
        case reclaimable = "Dev Junk"
        case categories = "Categories"
        case browse = "Browse"
        case treemap = "Treemap"
        case largeFiles = "Large Files"
        case search = "Search"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .systemData: "internaldrive"
            case .reclaimable: "hammer"
            case .categories: "square.grid.2x2"
            case .browse: "folder"
            case .treemap: "rectangle.split.3x3"
            case .largeFiles: "doc.on.doc"
            case .search: "magnifyingglass"
            }
        }
    }

    var phase: Phase = .welcome
    var section: Section = .systemData
    var scanPath = NSHomeDirectory()
    var isHomeScan = true
    /// The home-folder subtree within the scan — the root itself for home
    /// scans, /Users/<name> located inside a full-disk scan, nil otherwise.
    var homeNode: FileNode?
    var root: FileNode?
    var stats: ScanStats?
    var report: SystemDataReport?
    var categoryTotals: [CategoryTotal] = []
    var progressFiles = 0
    var progressBytes: Int64 = 0
    var scanDate: Date?
    var scanSeconds: Double = 0
    var volumeTotal: Int64 = 0
    var volumeFree: Int64 = 0
    /// Bumped whenever the in-memory tree is surgically updated after a
    /// trash/delete — views listening to it refresh instantly, no rescan.
    var treeVersion = 0
    private var pendingUndoNodes: [TreeSurgery.Removed] = []

    /// Size of ~/.Trash — kept current by tree surgery after cleans.
    var trashBytes: Int64 {
        _ = treeVersion
        return homeNode?.child(".Trash")?.size ?? 0
    }

    /// Update the tree and every derived view after the app removed `paths`
    /// from disk. Trash moves grow the .Trash node; permanent deletes shrink
    /// the totals outright.
    func applyRemoval(paths: [String], movedToTrash: Bool) {
        guard let root else { return }
        let result = TreeSurgery.remove(paths: paths, root: root, scanPath: scanPath)
        if movedToTrash {
            TreeSurgery.adjustTrash(by: result.bytes, root: root,
                                    scanPath: scanPath, homePath: NSHomeDirectory())
            pendingUndoNodes = result.removed
        } else {
            stats?.totalBytes -= result.bytes
            pendingUndoNodes = []
        }
        rebuildDerived()
        refreshVolumeInfo()
        treeVersion += 1
    }

    private func rebuildDerived() {
        guard let root else { return }
        let homePath = NSHomeDirectory()
        if let homeNode {
            report = SystemDataScan.build(homeRoot: homeNode, homePath: homePath)
            categoryTotals = Categorizer.homeTotals(root: homeNode)
        }
        devJunkItems = DevJunkScan.find(root: root, scanPath: scanPath,
                                        homeRoot: homeNode, homePath: homePath)
    }

    // MARK: - toast + undo

    struct Toast {
        let id = UUID()
        let message: String
        let undoItems: [TrashService.TrashedItem]?
    }

    var toast: Toast?
    var devJunkItems: [DevJunkItem] = []
    var fdaSheetPresented = false
    /// Absolute path the Browse section should open at.
    var browsePath: String?

    /// Open a location in the in-app Browse screen (review without Finder).
    func browse(_ path: String) {
        browsePath = path
        section = .browse
    }

    /// True when the last scan hit locked folders and FDA isn't granted.
    var showFDAHint: Bool {
        phase == .done && (stats?.skippedCount ?? 0) > 50 && !FullDiskAccess.isGranted
    }

    func showToast(_ message: String, undo: [TrashService.TrashedItem]? = nil) {
        let toast = Toast(message: message, undoItems: undo)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(15))
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
    }

    func undoLastClean() {
        guard let items = toast?.undoItems else { return }
        toast = nil
        let restored = TrashService.restore(items)
        if let root, !pendingUndoNodes.isEmpty {
            TreeSurgery.reattach(pendingUndoNodes, root: root, scanPath: scanPath)
            let bytes = pendingUndoNodes.reduce(Int64(0)) { $0 + $1.node.size }
            TreeSurgery.adjustTrash(by: -bytes, root: root,
                                    scanPath: scanPath, homePath: NSHomeDirectory())
            pendingUndoNodes = []
            rebuildDerived()
            refreshVolumeInfo()
            treeVersion += 1
        }
        showToast("Put back \(restored) of \(items.count) item\(items.count == 1 ? "" : "s") — numbers updated.")
    }

    init() {
        refreshVolumeInfo()
    }

    func refreshVolumeInfo() {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                          .volumeAvailableCapacityForImportantUsageKey]) {
            volumeTotal = Int64(values.volumeTotalCapacity ?? 0)
            volumeFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    func startScan(path: String) {
        scanPath = path
        isHomeScan = (path == NSHomeDirectory())
        phase = .scanning
        progressFiles = 0
        progressBytes = 0
        runScan(path: path, started: Date())
    }

    private func runScan(path: String, started: Date) {
        Task.detached(priority: .userInitiated) { [weak self, path] in
            let progress: @Sendable (Int, Int64) -> Void = { files, bytes in
                Task { @MainActor in
                    guard let self else { return }
                    self.progressFiles = files
                    self.progressBytes = bytes
                }
            }
            let result = try? ParallelScan.scan(path: path, onProgress: progress)
            let elapsed = Date().timeIntervalSince(started)
            Task { @MainActor in
                guard let self else { return }
                self.finishScan(result: result, elapsed: elapsed)
            }
        }
    }

    private func finishScan(result: ParallelScan.Result?, elapsed: Double) {
        guard let result else {
            phase = .welcome
            return
        }
        root = result.root
        stats = result.stats
        scanDate = Date()
        scanSeconds = elapsed

        // Locate the home subtree: the scan root itself, or /Users/<name>
        // inside a broader scan.
        let homePath = NSHomeDirectory()
        if isHomeScan {
            homeNode = result.root
        } else if homePath.hasPrefix(scanPath) {
            let relative = scanPath == "/" ? String(homePath.dropFirst())
                : String(homePath.dropFirst(scanPath.count + 1))
            var node: FileNode? = result.root
            for component in relative.split(separator: "/") {
                node = node?.child(String(component))
            }
            homeNode = node
        } else {
            homeNode = nil
        }

        if homeNode == nil {
            report = nil
            categoryTotals = []
        }
        section = homeNode != nil ? .systemData : .treemap
        pendingUndoNodes = []
        rebuildDerived()
        treeVersion += 1
        refreshVolumeInfo()
        phase = .done
    }
}
