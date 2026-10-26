import AppKit
import Core
import PerformanceUI
import SwiftUI

@main
struct ClearDiskApp: App {
    @NSApplicationDelegateAdaptor(UpdateAppDelegate.self) private var appDelegate
    @StateObject private var updater = AppUpdater()
    @State private var state = AppState()
    @State private var license = LicenseStore()
    @State private var iCloudDoctor = ICloudDoctorState()
    @State private var performance = PerformanceCoordinator()
    @State private var mainWindowVisible = false
    @AppStorage("performance.showMenuBar") private var showPerformanceMenu = false

    var body: some Scene {
        Window("ClearDisk", id: "main") {
            ContentView()
                .environment(state)
                .environment(license)
                .environment(iCloudDoctor)
                .environment(performance)
                .tint(UI.accent)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    appDelegate.state = state
                    appDelegate.iCloudDoctor = iCloudDoctor
                    appDelegate.performance = performance
                    performance.configure(isLicensed: { license.isLicensed },
                        requestUnlock: { license.showUnlock = true },
                        openStorage: {
                            state.openWorkspace(.storage)
                        },
                        openPerformance: {
                            state.openWorkspace(.performance)
                        },
                        fileOperationActive: { state.activeRemovals > 0 || iCloudDoctor.isOperating })
                    performance.configureStorage(summary: { state.storageMenuSummary },
                                                 open: { state.openStorageReview($0) })
                    performance.setMonitoring(visible: mainWindowVisible, menuBar: showPerformanceMenu)
                    updater.start()
                    license.load()
                    await license.recheckIfStale()
                }
                .onOpenURL { license.handle(url: $0) }
                .onAppear {
                    mainWindowVisible = true
                    performance.setMonitoring(visible: true, menuBar: showPerformanceMenu)
                }
                .onChange(of: showPerformanceMenu) { _, menu in
                    performance.setMonitoring(visible: mainWindowVisible, menuBar: menu)
                }
                .onDisappear {
                    mainWindowVisible = false
                    performance.cancelPendingMenuAction()
                    performance.setMonitoring(visible: false, menuBar: showPerformanceMenu)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("License…") { license.showUnlock = true }
                Divider()
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }.disabled(!updater.canCheckForUpdates)
            }
        }
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

    var activeRemovals = 0
    var showPermissions = false
    var showICloudDoctor = false
    var showMacChecks = false
    var showPerformance = false
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
        menuFiles = Self.largestMenuFiles(root: root, rootPath: scanPath)
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
    var menuFiles: [StorageMenuFile] = []
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

    /// Permissions is a destination, not a scan phase. A scan may finish
    /// while it is open, and Back must keep that result and the prior workspace.
    func showDiskAccess() {
        diskAccessConfirmed = false
        showPermissions = true
    }

    func leaveDiskAccess() {
        showPermissions = false
    }

    enum Workspace { case storage, iCloud, macChecks, performance }

    func openWorkspace(_ workspace: Workspace) {
        showPermissions = false
        showPerformance = workspace == .performance
        showICloudDoctor = workspace == .iCloud
        showMacChecks = workspace == .macChecks
    }

    var diskNavigationTitle: String {
        switch phase {
        case .welcome: "Disk scan"
        case .scanning: "Scan in progress"
        case .done: "Scan results"
        }
    }

    var permissionsReturnTitle: String {
        if showPerformance { return "Back to Why Slow" }
        if showMacChecks { return "Back to Mac checks" }
        if showICloudDoctor { return "Back to iCloud Doctor" }
        return phase == .done ? "Back to scan results" : "Back to disk scan"
    }

    var storageMenuSummary: StorageMenuSummary {
        let complete = phase == .done && root != nil
        return StorageMenuSummary(
            scanDate: complete ? scanDate : nil, isScanning: phase == .scanning,
            files: complete ? menuFiles : [],
            cacheBytes: complete ? report.map { report in
                report.rows.filter { ["app-caches", "browser-caches"].contains($0.id) }
                    .reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            } : nil,
            developerJunkBytes: complete ? devJunkItems.reduce(Int64(0)) { total, item in
                if case .trashable = item.action { return total + item.bytes }
                return total
            } : 0,
            location: complete ? scanPath : "", skippedCount: complete ? stats?.skippedCount ?? 0 : 0)
    }

    func openStorageReview(_ destination: StorageReviewDestination) {
        openWorkspace(.storage)
        guard phase != .scanning else { return }
        if case .scan = destination { showDiskAccess(); return }
        guard phase == .done, root != nil else { return }
        switch destination {
        case .largeFiles: section = .largeFiles
        case .developerJunk: section = .reclaimable
        case .caches:
            if homeNode != nil { section = .systemData }
            else { showDiskAccess() }
        case .scan: break
        }
    }

    /// Build before publishing a scan, or on the main actor after tree surgery.
    /// Only immutable value rows cross into PerformanceUI; no live tree is retained.
    nonisolated static func largestMenuFiles(root: FileNode, rootPath: String) -> [StorageMenuFile] {
        var largest: [StorageMenuFile] = []
        func walk(_ node: FileNode, path: String) {
            for child in node.children ?? [] where child.size >= 100_000_000 {
                let childPath = path == "/" ? "/" + child.name : path + "/" + child.name
                if child.isDirectory { walk(child, path: childPath) }
                else {
                    largest.append(StorageMenuFile(path: childPath, name: child.name, bytes: child.size))
                    largest.sort { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
                    if largest.count > 3 { largest.removeLast() }
                }
            }
        }
        walk(root, path: rootPath)
        return largest
    }

    func startScan(path: String) {
        openWorkspace(.storage)
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
            let menuFiles = Self.largestMenuFiles(root: result.root, rootPath: path)
            let elapsed = Date().timeIntervalSince(started)
            await MainActor.run { [weak self] in
                guard let self, self.scanRequest == request else { return }
                self.finishScan(result: result, home: home, report: report, categories: categories, junk: junk, menuFiles: menuFiles, elapsed: elapsed)
            }
        }
    }

    private func finishScan(result: ParallelScan.Result, home: FileNode?, report: SystemDataReport?, categories: [CategoryTotal], junk: [DevJunkItem], menuFiles: [StorageMenuFile], elapsed: Double) {
        root = result.root
        stats = result.stats
        scanDate = Date()
        scanSeconds = elapsed
        homeNode = home
        self.report = report
        categoryTotals = categories
        devJunkItems = junk
        self.menuFiles = menuFiles
        section = home != nil ? .systemData : .treemap
        pendingUndoNodes = []
        treeVersion += 1
        refreshVolumeInfo()
        phase = .done
    }
}
