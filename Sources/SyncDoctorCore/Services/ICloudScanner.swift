import Foundation

/// Recursively walks iCloud Drive and emits one `ICloudItem` per file/folder.
///
/// * Uses `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)`
///   with the ubiquity keys prefetched, so metadata comes back in the same
///   `getattrlist` pass the enumerator already does.
/// * Never opens files. Implicit materialization is switched off on the
///   scanning thread (`DatalessMaterializationPolicy`), so even a bug could
///   not trigger downloads.
/// * Never follows symlinks.
/// * Cancellation: cancel the consuming `Task`; the stream ends with a
///   `.finished` result flagged `wasCancelled`.
public struct ICloudScanner: Sendable {

    public init() {}

    /// Start a scan. Consume the returned stream with `for await`.
    public func scan(options: ScanOptions) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try DatalessMaterializationPolicy.withoutMaterialization {
                        Self.run(options: options, continuation: continuation)
                    }
                } catch {
                    continuation.yield(.finished(ScanResult(roots: options.roots, startedAt: Date(), finishedAt: Date(), items: [], issues: [ScanIssue(path: "", kind: .materializationPolicyUnavailable, error: ItemError(error))], wasCancelled: false, hitItemLimit: false)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience for callers that just want the final result.
    public func scanToResult(options: ScanOptions, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> ScanResult {
        let worker = Task.detached(priority: .userInitiated) {
            let (_, continuation) = AsyncStream<ScanEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
            do {
                return try DatalessMaterializationPolicy.withoutMaterialization {
                    Self.run(options: options, continuation: continuation, onProgress: onProgress)
                }
            } catch {
                return ScanResult(roots: options.roots, startedAt: Date(), finishedAt: Date(), items: [], issues: [ScanIssue(path: "", kind: .materializationPolicyUnavailable, error: ItemError(error))], wasCancelled: false, hitItemLimit: false)
            }
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }

    // MARK: - Worker

    @discardableResult
    private static func run(options: ScanOptions, continuation: AsyncStream<ScanEvent>.Continuation, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanResult {


        let started = Date()
        let fm = FileManager.default
        var items: [ICloudItem] = []
        var issues: [ScanIssue] = []
        var cancelled = false
        var hitLimit = options.roots.count > 64

        continuation.yield(.started(roots: options.roots))
        Log.scanner.info("Scan started roots=\(options.roots.count) descendPackages=\(options.descendIntoPackages) hidden=\(options.includeHidden)")

        var enumOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.descendIntoPackages { enumOptions.insert(.skipsPackageDescendants) }
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }

        if !options.descendIntoPackages || !options.includeHidden {
            issues.append(ScanIssue(path: "", kind: .coverageLimited, error: nil))
        }
        let limit = min(50_000, max(1, options.maxItems ?? 50_000))
        rootLoop: for root in options.roots.prefix(64) {
            if Task.isCancelled { cancelled = true; break }
            if items.count >= limit { hitLimit = true; break }
            guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
                issues.append(ScanIssue(path: root.path, kind: .rootUnreadable, error: nil)); continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                let issue = ScanIssue(path: root.path, kind: .rootMissing, error: nil)
                issues.append(issue)
                continuation.yield(.issue(issue))
                continue
            }

            // The root itself is an item too (gives us its container display name).
            let rootItem = ICloudMetadataReader.item(at: root, relativeTo: root, fresh: false)
            items.append(rootItem)
            continuation.yield(.item(rootItem))

            // Errors during enumeration are collected, not fatal. Returning
            // `true` tells the enumerator to keep going with the next entry.
            let issueBox = IssueBox()
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(ICloudMetadataReader.allKeys),
                options: enumOptions,
                errorHandler: { url, error in
                    let itemError = ItemError(error)
                    let kind: ScanIssueKind = itemError.looksLikePermissionDenied ? .permissionDenied : .enumerationFailed
                    issueBox.append(ScanIssue(path: url.path, kind: kind, error: itemError))
                    Log.scanner.error("Enumeration error at \(Log.path(url)): \(itemError.description)")
                    return true
                }
            ) else {
                let issue = ScanIssue(path: root.path, kind: .rootUnreadable, error: nil)
                issues.append(issue)
                continuation.yield(.issue(issue))
                continue
            }

            while true {
                if Task.isCancelled { cancelled = true; break rootLoop }
                if items.count >= limit { hitLimit = true; break rootLoop }
                guard let url = enumerator.nextObject() as? URL else { break }
                if Task.isCancelled { cancelled = true; break rootLoop }

                let item = ICloudMetadataReader.item(at: url, relativeTo: root, fresh: false)
                if item.kind == .symlink { enumerator.skipDescendants() }
                items.append(item)
                continuation.yield(.item(item))

                for issue in issueBox.drain() {
                    if issues.count < 1_000 { issues.append(issue) }
                    continuation.yield(.issue(issue))
                }

                if items.count % max(1, options.progressEvery) == 0 {
                    let progress = ScanProgress(itemsScanned: items.count, currentPath: url.path, elapsed: Date().timeIntervalSince(started))
                    continuation.yield(.progress(progress))
                    onProgress?(progress)
                }
                if items.count >= limit {
                    hitLimit = true
                    Log.scanner.notice("Scan stopped at maxItems=\(limit)")
                    break rootLoop
                }
            }
            for issue in issueBox.drain() {
                issues.append(issue)
                continuation.yield(.issue(issue))
            }
        }

        let result = ScanResult(roots: options.roots, startedAt: started, finishedAt: Date(), items: items, issues: issues, wasCancelled: cancelled, hitItemLimit: hitLimit)
        let s = result.summary
        Log.scanner.info("Scan finished items=\(s.totalItems) files=\(s.files) ubiquitous=\(s.ubiquitousItems) waiting=\(s.waitingToUpload) uploading=\(s.uploading) notDownloaded=\(s.notDownloaded) uploadErr=\(s.uploadErrors) downloadErr=\(s.downloadErrors) conflicts=\(s.unresolvedConflicts) issues=\(issues.count) cancelled=\(cancelled) in \(String(format: "%.2f", result.duration))s")
        continuation.yield(.finished(result))
        continuation.finish()
        return result
    }
}

/// The enumerator's error handler is a non-escaping-looking but actually
/// escaping closure invoked synchronously on the enumerating thread. A tiny
/// locked box keeps the compiler (and strict concurrency) happy.
private final class IssueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [ScanIssue] = []
    func append(_ issue: ScanIssue) { lock.lock(); if pending.count < 1_000 { pending.append(issue) }; lock.unlock() }
    func drain() -> [ScanIssue] {
        lock.lock(); defer { lock.unlock() }
        let out = pending; pending.removeAll(); return out
    }
}
