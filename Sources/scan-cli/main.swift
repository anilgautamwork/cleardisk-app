import Core
import Foundation

// scan-cli — proof harness for the ClearDisk scan engine.
// Usage: scan-cli <path> [--fm] [--top N]
//   --fm    use the slow FileManager reference scanner (baseline)
//   --top   how many largest children to print (default 15)

var path: String?
var useFM = false
var serial = false
var top = 15

var it = CommandLine.arguments.dropFirst().makeIterator()
while let arg = it.next() {
    switch arg {
    case "--fm": useFM = true
    case "--serial": serial = true
    case "--top": top = Int(it.next() ?? "") ?? top
    default: path = arg
    }
}

guard let target = path else {
    print("usage: scan-cli <path> [--fm] [--top N]")
    exit(2)
}

@Sendable func fmt(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    return String(format: "%.1f MB", Double(bytes) / 1_000_000)
}

let clock = ContinuousClock()
let start = clock.now

if useFM {
    let stats = ReferenceScanner.scan(path: target)
    let elapsed = clock.now - start
    print("engine: FileManager (baseline)")
    print("elapsed: \(elapsed)")
    print("files: \(stats.fileCount)  dirs: \(stats.directoryCount)  skipped: \(stats.skippedCount)")
    print("total: \(fmt(stats.totalBytes))  (\(stats.totalBytes) bytes)")
} else {
    do {
        let root: FileNode
        let stats: ScanStats
        let engine: String
        if serial {
            var options = BulkScanner.Options()
            options.skipPrefixes = BulkScanner.defaultRootSkips(for: target)
            options.onProgress = { files, bytes in
                FileHandle.standardError.write(Data("\r  … \(files) files, \(fmt(bytes))   ".utf8))
            }
            let scanner = BulkScanner(options: options)
            root = try scanner.scan(path: target)
            stats = scanner.stats
            engine = "getattrlistbulk (serial)"
        } else {
            let result = try ParallelScan.scan(path: target, onProgress: { files, bytes in
                FileHandle.standardError.write(Data("\r  … \(files) files, \(fmt(bytes))   ".utf8))
            })
            root = result.root
            stats = result.stats
            engine = "getattrlistbulk (parallel)"
        }
        let elapsed = clock.now - start
        FileHandle.standardError.write(Data("\r".utf8))
        print("engine: \(engine)")
        print("elapsed: \(elapsed)")
        print("files: \(stats.fileCount)  dirs: \(stats.directoryCount)  skipped: \(stats.skippedCount)")
        print("total: \(fmt(stats.totalBytes))  (\(stats.totalBytes) bytes)")
        print("")
        let biggest = (root.children ?? []).sorted { $0.size > $1.size }.prefix(top)
        for child in biggest {
            let marker = child.isDirectory ? "/" : ""
            print(String(format: "  %10@  %@%@", fmt(child.size) as NSString, child.name, marker))
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
}
