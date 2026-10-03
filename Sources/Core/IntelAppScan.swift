import Foundation

public enum AppArchitecture: String, Sendable {
    case intelOnly = "Intel-only"
    case legacyIntel = "32-bit Intel"
    case universal = "Universal"
    case appleSilicon = "Apple silicon"
    case unknown = "Not determined"
}

/// Reads only bounded Mach-O headers. Never launches an app or runs its tools.
public enum MachOArchitecture {
    public static func inspect(_ url: URL) -> AppArchitecture {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        do {
            let length = try handle.seekToEnd()
            func read(_ offset: UInt64, _ count: Int) throws -> Data {
                try handle.seek(toOffset: offset)
                return try handle.read(upToCount: count) ?? Data()
            }
            func word(_ data: Data, _ offset: Int, little: Bool = false) -> UInt32? {
                guard offset >= 0, offset + 4 <= data.count else { return nil }
                let indices = little ? Array((offset..<offset+4).reversed()) : Array(offset..<offset+4)
                return indices.reduce(UInt32(0)) { ($0 << 8) | UInt32(data[$1]) }
            }
            func wide(_ data: Data, _ offset: Int, little: Bool) -> UInt64? {
                guard let a = word(data, offset, little: little), let b = word(data, offset+4, little: little) else { return nil }
                return little ? (UInt64(b) << 32) | UInt64(a) : (UInt64(a) << 32) | UInt64(b)
            }
            func thinCPU(_ data: Data, size: UInt64) -> UInt32? {
                guard let magic = word(data, 0), [0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe].contains(magic) else { return nil }
                let little = magic == 0xcefaedfe || magic == 0xcffaedfe
                let headerSize: UInt64 = (magic == 0xfeedfacf || magic == 0xcffaedfe) ? 32 : 28
                guard size >= headerSize, data.count >= Int(headerSize), word(data, 12, little: little) == 2,
                      let commandBytes = word(data, 20, little: little), UInt64(commandBytes) <= size - headerSize else { return nil }
                return word(data, 4, little: little)
            }
            let header = try read(0, 32)
            guard let magic = word(header, 0) else { return .unknown }
            var cpus = Set<UInt32>()
            if [0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic) {
                let little = magic == 0xbebafeca || magic == 0xbfbafeca
                let is64 = magic == 0xcafebabf || magic == 0xbfbafeca
                guard let count = word(header, 4, little: little), count > 0, count <= 32 else { return .unknown }
                let stride = is64 ? 32 : 20
                let tableEnd = 8 + Int(count) * stride
                let table = try read(0, tableEnd)
                guard table.count == tableEnd else { return .unknown }
                var ranges: [Range<UInt64>] = []
                for i in 0..<Int(count) {
                    let base = 8 + i * stride
                    guard let cpu = word(table, base, little: little) else { return .unknown }
                    let offset = is64 ? wide(table, base+8, little: little) : word(table, base+8, little: little).map(UInt64.init)
                    let size = is64 ? wide(table, base+16, little: little) : word(table, base+12, little: little).map(UInt64.init)
                    guard let offset, let size, offset >= UInt64(tableEnd), offset <= length,
                          size >= 28, size <= length-offset else { return .unknown }
                    let range = offset..<(offset+size)
                    guard !ranges.contains(where: { $0.overlaps(range) }),
                          thinCPU(try read(offset, 32), size: size) == cpu else { return .unknown }
                    ranges.append(range)
                    cpus.insert(cpu)
                }
            } else if let cpu = thinCPU(header, size: length) { cpus.insert(cpu) }
            let intel = cpus.contains(0x01000007), arm = cpus.contains(0x0100000c)
            if arm { return intel ? .universal : .appleSilicon }
            if intel && cpus.isSubset(of: [7, 0x01000007]) { return .intelOnly }
            if cpus == [7] { return .legacyIntel }
            return .unknown
        } catch { return .unknown }
    }
}

public struct IntelAppReport: Sendable {
    public struct App: Identifiable, Sendable {
        public let path: String
        public let name: String
        public let version: String
        public let architecture: AppArchitecture
        public var id: String { path }
    }
    public let apps: [App]
    public let unavailablePaths: [String]
    public let roots: [String]
    public var intelApps: [App] { apps.filter { $0.architecture == .intelOnly } }
}

public enum IntelAppScan {
    public static var defaultRoots: [String] { ["/Applications", NSHomeDirectory() + "/Applications"] }

    public static func scan(roots: [String] = defaultRoots,
                            progress: @Sendable (String) -> Void = { _ in }) throws -> IntelAppReport {
        let fm = FileManager.default
        var apps: [IntelAppReport.App] = [], unavailable: [String] = []
        var seen = Set<String>()
        func inspect(_ candidate: URL) {
            let url = candidate.standardizedFileURL
            guard seen.insert(url.path).inserted else { return }
            progress(url.lastPathComponent)
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            // Bundle metadata is untrusted input. Do not allocate unbounded files
            // or follow an executable outside the app being inspected.
            let infoSize = (try? infoURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            let info = infoSize <= 1_048_576 && infoURL.resolvingSymlinksInPath().path.hasPrefix(url.path + "/")
                ? (try? Data(contentsOf: infoURL)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } : nil
            var architecture: AppArchitecture = .unknown
            if let executable = info?["CFBundleExecutable"] as? String, !executable.isEmpty,
               executable != ".", executable != "..", !executable.contains("/"), !executable.contains("\0") {
                let binary = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).resolvingSymlinksInPath()
                if binary.path.hasPrefix(url.path + "/"),
                   (try? binary.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    architecture = MachOArchitecture.inspect(binary)
                }
            }
            apps.append(.init(path: url.path,
                              name: info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
                              version: info?["CFBundleShortVersionString"] as? String ?? "Unknown version",
                              architecture: architecture))
        }
        for root in roots {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: root).standardizedFileURL
            // Missing ~/Applications is ordinary; unreadable roots are not a clean scan.
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      url.resolvingSymlinksInPath().path == url.path else { unavailable.append(url.path); continue }
            } catch {
                if (error as NSError).code != NSFileReadNoSuchFileError { unavailable.append(url.path) }
                continue
            }
            if url.pathExtension.lowercased() == "app" { inspect(url); continue }
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                 options: [.skipsHiddenFiles], errorHandler: { url, _ in unavailable.append(url.path); return true }) else {
                unavailable.append(url.path); continue
            }
            for case let child as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                    unavailable.append(child.path); continue
                }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isDirectory == true else { continue }
                if child.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    inspect(child)
                } else if child.pathExtension.lowercased() == "bundle" || child.pathExtension.lowercased() == "framework" {
                    enumerator.skipDescendants()
                }
            }
        }
        let priority: [AppArchitecture: Int] = [.intelOnly: 0, .legacyIntel: 1, .unknown: 2, .universal: 3, .appleSilicon: 3]
        return .init(apps: apps.sorted {
            let a = priority[$0.architecture, default: 3], b = priority[$1.architecture, default: 3]
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
        },
                     unavailablePaths: Array(Set(unavailable)).sorted(), roots: roots)
    }
}
