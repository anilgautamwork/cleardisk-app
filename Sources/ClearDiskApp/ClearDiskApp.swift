import Core
import SwiftUI

@main
struct ClearDiskApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("ClearDisk") {
            ContentView()
                .environment(state)
                .tint(UI.accent)
                .preferredColorScheme(.dark)
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
        case diskAccess
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
    var scanStage = "Reading files"
    private var scanRequest = UUID()
    private var scanTask: Task<Void, Never>?
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
    var diskAccessConfirmed = false
    /// Absolute path the Browse section should open at.
    var browsePath: String?

    /// Open a location in the in-app Browse screen (review without Finder).
    func browse(_ path: String) {
        browsePath = path
        section = .browse
    }

    /// True when the last scan hit locked folders and FDA isn't granted.
    var showFDAHint: Bool {
        phase == .done && (stats?.skippedCount ?? 0) > 50 && !FullDiskAccess.isConfirmed
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
        guard let items = toast?.undoItems, !items.isEmpty else { return }
        toast = nil
        let result = TrashService.restoreReporting(items)
        if let root, !pendingUndoNodes.isEmpty {
            let bytes = TreeSurgery.reattachRestored(pendingUndoNodes,
                                                    originalPaths: result.restoredPaths,
                                                    root: root, scanPath: scanPath)
            TreeSurgery.adjustTrash(by: -bytes, root: root,
                                    scanPath: scanPath, homePath: NSHomeDirectory())
            if !result.restoredPaths.isEmpty {
                rebuildDerived()
                refreshVolumeInfo()
                treeVersion += 1
            }
        }
        // Retain only failures with a real Trash URL for a possible retry.
        // A missing undo URL cannot restore a node or reduce the Trash count.
        let retryPaths = Set(result.failedItems.map(\.originalPath))
        pendingUndoNodes = pendingUndoNodes.filter { retryPaths.contains($0.originalPath) }
        let restored = result.restoredPaths.count
        if result.failures.isEmpty {
            showToast("Put back \(restored) of \(items.count) item\(items.count == 1 ? "" : "s").")
        } else {
            let detail = result.failures.first ?? ""
            showToast("Put back \(restored) of \(items.count) items. \(result.failures.count) couldn’t be restored. \(detail)",
                      undo: result.failedItems)
        }
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

    func showDiskAccess() {
        diskAccessConfirmed = false
        phase = .diskAccess
    }

    func leaveDiskAccess() {
        phase = root == nil ? .welcome : .done
    }

    func startScan(path: String) {
        // Gate full-disk work here, so welcome, rescan, and choosing "/" in
        // the folder picker cannot enter the scanner before access is checked.
        let decision = ScanAccessPolicy.decision(path: path, diskAccessConfirmed: FullDiskAccess.isConfirmed)
        guard case .scan(let path) = decision else {
            showDiskAccess()
            return
        }
        scanTask?.cancel()
        scanRequest = UUID()
        scanStage = "Reading files"
        scanPath = path
        isHomeScan = (path == NSHomeDirectory())
        phase = .scanning
        progressFiles = 0
        progressBytes = 0
        runScan(path: path, started: Date())
    }

    private func runScan(path: String, started: Date) {
        let request = scanRequest
        let homePath = NSHomeDirectory()
        scanTask = Task.detached(priority: .userInitiated) { [weak self, path] in
            let progress: @Sendable (Int, Int64) -> Void = { files, bytes in
                Task { @MainActor in
                    guard let self, self.scanRequest == request, self.scanStage == "Reading files" else { return }
                    self.progressFiles = max(self.progressFiles, files)
                    self.progressBytes = max(self.progressBytes, bytes)
                }
            }
            guard let result = try? ParallelScan.scan(path: path, onProgress: progress), !Task.isCancelled else {
                await MainActor.run { [weak self] in
                    guard let self, self.scanRequest == request else { return }
                    self.phase = .welcome
                    self.showToast("This location couldn’t be read. Choose another folder or check access.")
                }
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.scanRequest == request else { return }
                self.scanStage = "Organizing your storage"
                self.progressFiles = result.stats.fileCount
                self.progressBytes = result.stats.totalBytes
            }
            // The result has not been published to AppState yet. This worker
            // exclusively owns the tree while the recursive reports are built.
            let home: FileNode?
            if path == homePath { home = result.root }
            else if path == "/" || homePath.hasPrefix(path + "/") {
                let relative = path == "/" ? String(homePath.dropFirst()) : String(homePath.dropFirst(path.count + 1))
                var node: FileNode? = result.root
                for component in relative.split(separator: "/") { node = node?.child(String(component)) }
                home = node
            } else { home = nil }
            let report = home.map { SystemDataScan.build(homeRoot: $0, homePath: homePath) }
            let categories = home.map { Categorizer.homeTotals(root: $0) } ?? []
            guard !Task.isCancelled else { return }
            let junk = DevJunkScan.find(root: result.root, scanPath: path, homeRoot: home, homePath: homePath)
            guard !Task.isCancelled else { return }
            let elapsed = Date().timeIntervalSince(started)
            await MainActor.run { [weak self] in
                guard let self, self.scanRequest == request else { return }
                self.finishScan(result: result, home: home, report: report, categories: categories, junk: junk, elapsed: elapsed)
            }
        }
    }

    private func finishScan(result: ParallelScan.Result, home: FileNode?, report: SystemDataReport?, categories: [CategoryTotal], junk: [DevJunkItem], elapsed: Double) {
        root = result.root
        stats = result.stats
        scanDate = Date()
        scanSeconds = elapsed
        homeNode = home
        self.report = report
        categoryTotals = categories
        devJunkItems = junk
        section = home != nil ? .systemData : .treemap
        pendingUndoNodes = []
        treeVersion += 1
        refreshVolumeInfo()
        phase = .done
    }
}
