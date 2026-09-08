import AppKit
import Foundation
import Network
import SyncDoctorCore

/// Independent of the disk scanner. No iCloud API is called until Scan is clicked.
@MainActor
@Observable
final class ICloudDoctorState {
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All items", problems = "Errors & conflicts", waiting = "Waiting & transfers"
        case cloudOnly = "Cloud only", local = "Local copies", large = "Over 100 MB"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case local = "Local bytes", logical = "File size", name = "Name", oldest = "Oldest modified"
        var id: String { rawValue }
    }
    struct FolderTotal: Identifiable, Sendable {
        let path: String
        let relativePath: String
        var files = 0
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var unknownSizes = 0
        var id: String { path }
    }
    var result: ScanResult?
    var location: ICloudDriveLocation?
    var isScanning = false
    var isCancelling = false
    var scannedCount = 0
    var progressPath = ""
    var search = ""
    var filter: Filter = .all
    var sort: Sort = .local
    var olderThanDays = 0
    var selectedPath: String?
    var folderTotals: [FolderTotal] = []
    var stuckPaths: Set<String> = []
    var operationMessage: String?
    var operationFailed = false
    var isOperating = false
    var operationLabel = ""
    var archivedOriginal: URL?
    var archiveURL: URL?
    var networkStatus = "Not checked"
    var historyMessage: String?
    var history = PendingHistory()
    private var scanTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()
    private var networkMonitor: NWPathMonitor?

    var selectedItem: ICloudItem? { result?.items.first { $0.path == selectedPath } }
    var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClearDisk/iCloud-history.json")
    }

    func startScan() {
        guard !isScanning, !isOperating else { return }
        isScanning = true
        isCancelling = false
        scannedCount = 0
        progressPath = "Locating iCloud Drive…"
        selectedPath = nil
        result = nil
        folderTotals = []
        let id = UUID()
        requestID = id
        checkNetwork()
        let savedHistoryURL = historyURL
        scanTask = Task {
            let (found, savedHistory) = await Task.detached(priority: .userInitiated) {
                let location = ICloudDriveLocator.locate()
                let saved = (try? Data(contentsOf: savedHistoryURL)).flatMap { try? JSONDecoder().decode(PendingHistory.self, from: $0) }
                return (location, saved ?? PendingHistory())
            }.value
            guard requestID == id else { return }
            location = found
            var options = ScanOptions(roots: [found.rootURL])
            options.maxItems = 50_000
            options.progressEvery = 250
            let scan = await ICloudScanner().scanToResult(options: options) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.requestID == id, self.isScanning else { return }
                    self.scannedCount = progress.itemsScanned
                    self.progressPath = progress.currentPath
                }
            }
            guard requestID == id else { return }
            let (updatedHistory, stuck, folders, saveError) = await Task.detached(priority: .utility) {
                var updated = savedHistory
                updated.record(scan)
                let error = Self.writeHistory(updated, to: savedHistoryURL)
                return (updated, updated.potentiallyStuckPaths(), Self.aggregateFolders(scan), error)
            }.value
            result = scan
            scannedCount = scan.items.count
            history = updatedHistory
            stuckPaths = stuck
            folderTotals = folders
            historyMessage = saveError
            isScanning = false
            isCancelling = false
            scanTask = nil
        }
    }

    func cancelScan() {
        isCancelling = true
        scanTask?.cancel()
    }

    func clearHistory() {
        history = PendingHistory()
        stuckPaths = []
        persistHistory()
        if historyMessage == nil { historyMessage = "Local observation history cleared." }
    }

    private func persistHistory() {
        historyMessage = Self.writeHistory(history, to: historyURL)
    }

    nonisolated private static func writeHistory(_ history: PendingHistory, to url: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return nil
        } catch {
            return "Couldn’t save local history: \(error.localizedDescription)"
        }
    }

    private func checkNetwork() {
        networkMonitor?.cancel()
        networkStatus = "Checking…"
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status == .satisfied ? "Network route available" : "No network route observed"
            monitor.cancel()
            Task { @MainActor in self?.networkStatus = status }
        }
        monitor.start(queue: DispatchQueue(label: "app.cleardisk.icloud-network"))
    }

    nonisolated static func aggregateFolders(_ scan: ScanResult) -> [FolderTotal] {
        var totals: [String: FolderTotal] = [:]
        for item in scan.items where item.kind == .directory {
            totals[item.path] = FolderTotal(path: item.path, relativePath: item.relativePath.isEmpty ? "iCloud Drive" : item.relativePath)
        }
        for item in scan.items where item.kind == .file {
            var parent = item.url.deletingLastPathComponent().path
            while parent != "/" {
                guard var total = totals[parent] else { break }
                total.files += 1
                total.allocated += item.allocatedSize ?? 0
                total.logical += item.logicalSize ?? 0
                if item.allocatedSize == nil || item.logicalSize == nil { total.unknownSizes += 1 }
                totals[parent] = total
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return totals.values.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }
    }

    nonisolated static func visibleItems(_ items: [ICloudItem], search: String, filter: Filter, sort: Sort, olderThanDays: Int) -> [ICloudItem] {
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        return items.filter { item in
            if !search.isEmpty && !item.relativePath.localizedStandardContains(search) && !item.name.localizedStandardContains(search) { return false }
            if olderThanDays > 0 && (item.modificationDate == nil || item.modificationDate! > cutoff) { return false }
            switch filter {
            case .all: return true
            case .problems: return !isICloudMetadataNoise(item) && (item.hasAnyError || item.hasUnresolvedConflicts == true)
            case .waiting: return !isICloudMetadataNoise(item) && (item.isWaitingToUpload || item.isUploading == true || item.isDownloading == true)
            case .cloudOnly: return item.locality == .cloudOnly
            case .local: return item.kind == .file && item.locality == .local
            case .large: return item.kind == .file && (item.logicalSize ?? 0) >= 100_000_000
            }
        }.sorted { a, b in
            switch sort {
            case .name: return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
            case .oldest:
                let left = a.modificationDate ?? .distantFuture, right = b.modificationDate ?? .distantFuture
                return left == right ? a.path < b.path : left < right
            case .local:
                let left = a.allocatedSize ?? -1, right = b.allocatedSize ?? -1
                return left == right ? a.path < b.path : left > right
            case .logical:
                let left = a.logicalSize ?? -1, right = b.logicalSize ?? -1
                return left == right ? a.path < b.path : left > right
            }
        }
    }

    enum Action: String, Identifiable {
        case download = "Download Now", evict = "Remove Local Download", archive = "Archive to Mac"
        var id: String { rawValue }
    }

    /// Called only after the confirmation sheet. License status is refreshed and
    /// checked again immediately before dispatching a licensed file operation.
    func perform(_ action: Action, item: ICloudItem, destination: URL?, license: LicenseStore) {
        guard !isOperating, !isScanning else { return }
        isOperating = true
        operationFailed = false
        operationMessage = nil
        operationLabel = action.rawValue
        archivedOriginal = nil
        archiveURL = nil
        operationTask = Task {
            if action != .download {
                await license.recheckIfStale()
                guard license.isLicensed else {
                    isOperating = false
                    license.showUnlock = true
                    operationMessage = "Activate your ClearDisk license, then review this action again."
                    return
                }
            }
            guard !Task.isCancelled else { isOperating = false; return }
            let worker = Task.detached(priority: .userInitiated) { () throws -> (ArchiveReceipt?, ICloudItem?) in
                try Task.checkCancellation()
                switch action {
                case .download: try ICloudFileActions.requestDownload(of: item.url)
                case .evict: try ICloudFileActions.evictLocalCopy(of: item.url)
                case .archive:
                    guard let destination else { throw CocoaError(.fileNoSuchFile) }
                    return (try VerifiedArchive.create(source: item.url, destinationDirectory: destination, cancellation: { Task.isCancelled }), nil)
                }
                let observed = try? DatalessMaterializationPolicy.withoutMaterialization {
                    ICloudMetadataReader.item(at: item.url, relativeTo: nil)
                }
                return (nil, observed)
            }
            do {
                let (receipt, observed) = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                if let receipt {
                    archivedOriginal = item.url
                    archiveURL = receipt.archiveURL
                    operationMessage = "Verified \(receipt.fileCount.formatted()) files (\(fmtBytes(receipt.verifiedBytes))) at \(receipt.archiveURL.path). Your iCloud original is unchanged. This copy has not freed iCloud storage."
                } else {
                    operationMessage = action == .download
                        ? "Download request accepted. This is not a completed download. Scan again to observe the current state."
                        : "Local removal request accepted. Scan again to observe local allocated bytes; no space savings are assumed."
                    if let observed {
                        operationMessage! += " Observed after the request: \(iCloudStateLabel(observed)), local allocation \(observed.allocatedSize.map(fmtBytes) ?? "Unknown"). macOS may update this later."
                    }
                }
            } catch {
                operationFailed = true
                operationMessage = error.localizedDescription
            }
            isOperating = false
            operationTask = nil
        }
    }

    func cancelOperation() { operationTask?.cancel() }
}

nonisolated func isICloudMetadataNoise(_ item: ICloudItem) -> Bool {
    item.name == ".DS_Store" || item.name.hasPrefix("._")
}

func iCloudStateLabel(_ item: ICloudItem, stuck: Bool = false) -> String {
    if isICloudMetadataNoise(item) { return "Finder metadata" }
    if item.accessError != nil { return "Access denied / unreadable" }
    if item.hasUnresolvedConflicts == true { return "Conflict" }
    if item.uploadError != nil { return "Upload error" }
    if item.downloadError != nil { return "Download error" }
    if stuck { return "Potentially stuck" }
    if item.isUploading == true { return "Uploading" }
    if item.isDownloading == true { return "Downloading" }
    if item.isWaitingToUpload { return "Waiting to upload" }
    return item.locality.displayName
}
