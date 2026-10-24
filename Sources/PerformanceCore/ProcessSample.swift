import Foundation

/// One row of `/bin/ps` output. `ps` is setuid root, so it sees system
/// processes (WindowServer, mds_stores) that an unprivileged app can't read.
public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let uid: UInt32
    public let user: String
    /// Cumulative CPU seconds since the process started.
    public let cpuTime: TimeInterval
    public let rssBytes: Int64
    /// `ps`'s own decayed %cpu — only used when there's no previous sample.
    public let psCPU: Double
    /// Full executable path (`comm`), spaces kept.
    public let path: String

    /// Last path component, sliced without bridging through NSString.
    public var name: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    public init(pid: Int32, ppid: Int32, uid: UInt32, user: String, cpuTime: TimeInterval,
                rssBytes: Int64, psCPU: Double, path: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.user = user
        self.cpuTime = cpuTime
        self.rssBytes = rssBytes
        self.psCPU = psCPU
        self.path = path
    }
}

public struct Snapshot: Sendable {
    public let takenAt: Date
    public let processes: [ProcessSample]

    public init(takenAt: Date, processes: [ProcessSample]) {
        self.takenAt = takenAt
        self.processes = processes
    }
}

public enum PSParser {
    /// Parses `ps -axo pid=,ppid=,uid=,user=,time=,rss=,%cpu=,comm=` output.
    /// Lines that don't parse are skipped, never fatal.
    public static func parse(_ text: String) -> [ProcessSample] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard f.count == 8,
                  let pid = Int32(f[0]), let ppid = Int32(f[1]), let uid = UInt32(f[2]),
                  let cpu = cpuSeconds(String(f[4])), let rssKB = Int64(f[5]), let pct = Double(f[6])
            else { return nil }
            return ProcessSample(pid: pid, ppid: ppid, uid: uid, user: String(f[3]), cpuTime: cpu,
                                 rssBytes: rssKB * 1024, psCPU: pct, path: String(f[7]))
        }
    }

    /// `M:SS.ss` (minutes may exceed 59, e.g. `590:13.92`) or `H:MM:SS.ss`.
    public static func cpuSeconds(_ field: String) -> TimeInterval? {
        let parts = field.split(separator: ":").map { Double($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }
}

public protocol ProcessSource: Sendable {
    func sample() throws -> Snapshot
}

public enum SamplerError: Error, Equatable {
    case psFailed(Int32)
}

public struct PSProcessSource: ProcessSource {
    public init() {}

    public func sample() throws -> Snapshot {
        let output = try Shell.run("/bin/ps", ["-axo", "pid=,ppid=,uid=,user=,time=,rss=,%cpu=,comm="])
        guard output.status == 0 else { throw SamplerError.psFailed(output.status) }
        return Snapshot(takenAt: Date(), processes: PSParser.parse(output.stdout))
    }
}

extension PSProcessSource {
    /// `ps -axo pid=,rss=,args=` — full command lines, used to spot browser extension processes.
    public static func argsListing() throws -> String {
        try Shell.run("/bin/ps", ["-axo", "pid=,rss=,args="]).stdout
    }

    /// `launchctl list` for the current user → label: pid of running jobs.
    public static func launchctlList() throws -> [String: Int32] {
        BackgroundItemsReader.parseLaunchctlList(try Shell.run("/bin/launchctl", ["list"]).stdout)
    }
}

/// Runs a system tool and captures its output. Reads stdout before waiting so
/// a large output (1,000+ processes) can't fill the pipe and deadlock.
enum Shell {
    enum Failure: Error { case timedOut }

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var contents = Data()
        func write(_ data: Data) { lock.lock(); defer { lock.unlock() }; contents = data }
        func read() -> Data { lock.lock(); defer { lock.unlock() }; return contents }
    }
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 45) throws -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let output = Capture(), errors = Capture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async {
            output.write(out.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            errors.write(err.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning {
            p.terminate()
            let grace = Date().addingTimeInterval(1)
            while p.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            _ = readers.wait(timeout: .now() + 2)
            throw Failure.timedOut
        }
        p.waitUntilExit()
        guard readers.wait(timeout: .now() + 2) == .success else { throw Failure.timedOut }
        let o = output.read(), e = errors.read()
        return Output(status: p.terminationStatus,
                      stdout: String(decoding: o, as: UTF8.self),
                      stderr: String(decoding: e, as: UTF8.self))
    }
}
