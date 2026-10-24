import PerformanceCore
import SwiftUI

/// Is it the Mac, the Wi-Fi, or the internet line?
struct InternetView: View {
    @Environment(Monitor.self) private var monitor
    @State private var link: LinkType?
    @State private var wifi: WiFiLink?
    @State private var usage: [NetUsage] = []
    @State private var usageLoaded = false
    @State private var usageError: String?
    @State private var speed: SpeedResult? = InternetView.savedSpeed
    @State private var testing = false
    @State private var testError: String?
    @State private var askTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Internet").font(.system(size: 30, weight: .bold))
                    Text("Find out if it's your Mac, your Wi-Fi, or your internet line.").font(.system(size: 14.5)).foregroundStyle(Theme.text2)
                }
                findingsCard
                HStack(alignment: .top, spacing: 16) {
                    linkCard
                    speedCard
                }
                appsCard
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
        .task {
            // Link and per-app use refresh while the screen is open; nettop takes ~5s per read.
            while !Task.isCancelled {
                link = await LinkReader.currentType()
                wifi = LinkReader.wifi()
                guard !Task.isCancelled else { return }
                do {
                    let sample = try await NetTop.sample()
                    guard !Task.isCancelled else { return }
                    usage = sample
                    usageError = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    usage = []
                    usageError = "Per-app bandwidth could not be read. It will retry while this screen is open."
                }
                usageLoaded = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Test your internet speed?", isPresented: $askTest) {
            Button("Run test") { Task { await runTest() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ClearDisk uses Apple's built-in test against Apple's servers. It takes about 25 seconds and can use several hundred MB of data on fast connections.")
        }
    }

    // MARK: Cards

    private var findings: [Finding] {
        guard let link else { return [] }
        // A speed result only counts toward the verdict for an hour; older ones are shown, not judged.
        let recent = speed.flatMap { Date().timeIntervalSince($0.measuredAt) < 3600 ? $0 : nil }
        return InternetDiagnosis.run(link: link, wifi: wifi, speed: recent, usage: usage, appName: appName)
    }

    private var findingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if link == nil {
                    Text("Checking your connection…").font(.system(size: 20, weight: .bold))
                } else if findings.isEmpty {
                    Label("No issue detected in these readings.", systemImage: "checkmark.seal").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.green)
                    Text(speed.map { Date().timeIntervalSince($0.measuredAt) < 3600 } == true
                         ? "The connection readings and recent speed test did not flag a problem. Individual websites can still have issues."
                         : "Your internet speed has not been checked recently. Run a speed test to check it; these readings alone cannot confirm every website is reachable.")
                        .font(.system(size: 14)).foregroundStyle(Theme.text2)
                } else {
                    ForEach(findings) { f in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: f.kind.symbol).foregroundStyle(Theme.color(f.severity)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.headline).font(.system(size: 15, weight: .semibold))
                                Text(f.detail).font(.system(size: 13)).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            if let fix = f.primaryFix { FixButton(fix: fix, group: nil) }
                        }
                    }
                }
            }
        }
    }

    private var linkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Connection")
                switch link {
                case .wifi?:
                    Text("Wi-Fi").font(.system(size: 22, weight: .bold))
                    if let w = wifi {
                        row("Signal", "\(w.quality.label) (\(w.rssi) dBm)", color: w.quality >= .good ? Theme.green : w.quality == .fair ? Theme.amber : Theme.red)
                        row("Band", w.band.label)
                        row("Wi-Fi link", "\(Int(w.transmitRateMbps)) Mbps between your Mac and router")
                    }
                case .ethernet?: Text("Wired connection").font(.system(size: 22, weight: .bold))
                case .other?: Text("Connected").font(.system(size: 22, weight: .bold))
                case .offline?: Text("Offline").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.red)
                case nil: ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Speed test")
                if testing {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Testing your connection…") }
                        .font(.system(size: 14))
                } else if let s = speed {
                    row("Download", "\(Int(s.downloadMbps.rounded())) Mbps")
                    row("Upload", "\(Int(s.uploadMbps.rounded())) Mbps")
                    if let rpm = s.responsivenessRPM { row("Responsiveness", "\(Responsiveness(rpm: rpm).label) (\(rpm) RPM)") }
                    if let rtt = s.baseRTTms { row("Latency", "\(Int(rtt.rounded())) ms") }
                    Text("Last tested \(s.measuredAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                } else {
                    Text("See your real download and upload speed.").font(.system(size: 14)).foregroundStyle(Theme.text2)
                }
                if let testError { Text(testError).font(.system(size: 12.5)).foregroundStyle(Theme.amber) }
                Button { askTest = true } label: { Label("Run speed test", systemImage: "speedometer") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(testing)
            }
        }
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps using your connection").font(.system(size: 17, weight: .bold))
            if !usageLoaded {
                ProgressView().controlSize(.small)
            } else if let usageError {
                Text(usageError).font(.system(size: 13.5)).foregroundStyle(Theme.amber)
            } else if usage.filter({ $0.total >= 10_000 }).isEmpty {
                Text("Nothing is using much bandwidth right now.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            } else {
                ForEach(Array(byApp.prefix(5).enumerated()), id: \.offset) { _, u in
                    HStack {
                        Text(u.name).font(.system(size: 13.5))
                        Spacer()
                        Label("\(Format.bytes(Int64(u.bytesInPerSec)))/s", systemImage: "arrow.down").frame(width: 130, alignment: .trailing)
                        Label("\(Format.bytes(Int64(u.bytesOutPerSec)))/s", systemImage: "arrow.up").frame(width: 130, alignment: .trailing)
                    }
                    .font(.system(size: 13)).monospacedDigit()
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Theme.card)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
    }

    /// One row per app: an app's several networking processes add up.
    private var byApp: [NetUsage] {
        Dictionary(grouping: usage) { appName($0.pid) ?? $0.name }
            .map { name, list in
                NetUsage(pid: list[0].pid, name: name, bytesInPerSec: list.reduce(0) { $0 + $1.bytesInPerSec },
                         bytesOutPerSec: list.reduce(0) { $0 + $1.bytesOutPerSec })
            }
            .sorted { $0.total > $1.total }
    }

    private func row(_ k: String, _ v: String, color: Color = Theme.text) -> some View {
        HStack {
            Text(k).foregroundStyle(Theme.text2)
            Spacer()
            Text(v).foregroundStyle(color)
        }
        .font(.system(size: 13.5))
    }

    private func appName(_ pid: Int32) -> String? {
        monitor.groups.first { $0.members.contains { $0.pid == pid } }?.displayName
    }

    // MARK: Speed test

    private func runTest() async {
        testing = true
        testError = nil
        defer { testing = false }
        do {
            let r = try await SpeedTest.run()
            speed = r
            if let data = try? JSONEncoder().encode(r) { UserDefaults.standard.set(data, forKey: "lastSpeedTest") }
        } catch {
            testError = "The speed test didn't finish. Check your connection and try again."
        }
    }

    static var savedSpeed: SpeedResult? {
        UserDefaults.standard.data(forKey: "lastSpeedTest").flatMap { try? JSONDecoder().decode(SpeedResult.self, from: $0) }
    }
}
