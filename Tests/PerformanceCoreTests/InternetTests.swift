import XCTest
@testable import PerformanceCore

final class InternetTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1000)

    func wifi(_ rssi: Int, band: WiFiBand = .ghz5) -> WiFiLink {
        WiFiLink(rssi: rssi, noise: -94, transmitRateMbps: 600, band: band)
    }

    func speed(_ down: Double, rpm: Int? = 1500) -> SpeedResult {
        SpeedResult(downloadMbps: down, uploadMbps: 20, responsivenessRPM: rpm, baseRTTms: 20, measuredAt: t)
    }

    func diag(link: LinkType = .wifi, wifi w: WiFiLink? = nil, speed s: SpeedResult? = nil, usage: [NetUsage] = []) -> [Finding] {
        InternetDiagnosis.run(link: link, wifi: w ?? wifi(-55), speed: s, usage: usage, appName: { _ in nil })
    }

    func testSignalQuality() {
        XCTAssertEqual(SignalQuality(rssi: -55), .excellent)
        XCTAssertEqual(SignalQuality(rssi: -65), .good)
        XCTAssertEqual(SignalQuality(rssi: -75), .fair)
        XCTAssertEqual(SignalQuality(rssi: -85), .poor)
    }

    func testResponsiveness() {
        XCTAssertEqual(Responsiveness(rpm: 1200), .high)
        XCTAssertEqual(Responsiveness(rpm: 500), .medium)
        XCTAssertEqual(Responsiveness(rpm: 100), .low)
    }

    func testParseSpeedFixture() throws {
        let r = try SpeedTest.parse(Data(contentsOf: fixtureURL("networkquality.json")), at: t)
        XCTAssertEqual(r.downloadMbps, 245)
        XCTAssertEqual(r.uploadMbps, 38)
        XCTAssertEqual(r.responsivenessRPM, 850)
        XCTAssertEqual(r.baseRTTms, 18.5)
    }

    func testParseRealNetworkQualityOutput() throws {
        // Captured from /usr/bin/networkQuality -c on macOS 27: responsiveness is a decimal.
        let r = try SpeedTest.parse(Data(contentsOf: fixtureURL("networkquality-real.json")), at: t)
        XCTAssertEqual(r.downloadMbps, 92.85, accuracy: 0.01)
        XCTAssertEqual(r.uploadMbps, 39.68, accuracy: 0.01)
        XCTAssertEqual(r.responsivenessRPM, 109)
        XCTAssertEqual(r.baseRTTms ?? 0, 283.6, accuracy: 0.1)
        XCTAssertEqual(Responsiveness(rpm: r.responsivenessRPM!), .low)
    }

    func testParseSpeedMissingThrows() {
        XCTAssertThrowsError(try SpeedTest.parse(Data("{}".utf8), at: t)) { XCTAssertEqual($0 as? SpeedTestError, .unreadable) }
        XCTAssertThrowsError(try SpeedTest.parse(Data("nope".utf8), at: t))
    }

    func testParseNettopUsesLastBlock() throws {
        let u = NetTop.parse(try fixture("nettop.csv"))
        XCTAssertEqual(u.first?.name, "com.apple.WebKit.Networking")
        XCTAssertEqual(u.first?.pid, 4321)
        XCTAssertEqual(u.first?.total, 700_000)
        XCTAssertEqual(u.first { $0.pid == 640 }?.total, 4000)
        XCTAssertEqual(u.first { $0.pid == 93313 }?.name, "Codex (Service)")
        XCTAssertFalse(u.contains { $0.total == 0 })
    }

    func testOffline() {
        let f = diag(link: .offline, wifi: nil)
        XCTAssertEqual(f.map(\.kind), [.offline])
        XCTAssertEqual(f.first?.headline, "You're offline.")
        XCTAssertEqual(f.first?.severity, .high)
        XCTAssertEqual(f.first?.primaryFix, .openWiFiSettings)
    }

    func testWeakWiFi() {
        let poor = diag(wifi: wifi(-85)).first { $0.kind == .weakWiFi }
        XCTAssertEqual(poor?.headline, "Your Wi-Fi signal is weak.")
        XCTAssertEqual(poor?.severity, .high)
        XCTAssertEqual(poor?.detail, "Move closer to your router or remove obstacles. Signal: -85 dBm.")
        let fair = diag(wifi: wifi(-75)).first { $0.kind == .weakWiFi }
        XCTAssertEqual(fair?.headline, "Your Wi-Fi signal is only fair.")
        XCTAssertEqual(fair?.severity, .medium)
    }

    func testBand24Tip() {
        let f = diag(wifi: wifi(-55, band: .ghz2_4))
        XCTAssertEqual(f.map(\.kind), [.band24])
        XCTAssertEqual(f.first?.headline, "You're on 2.4 GHz Wi-Fi.")
        XCTAssertEqual(f.first?.severity, .low)
    }

    func testSlowLine() {
        let good = diag(speed: speed(6)).first { $0.kind == .slowLine }
        XCTAssertEqual(good?.headline, "Your internet is slow: 6 Mbps down.")
        XCTAssertEqual(good?.detail, "Your Wi-Fi is fine, so the slowdown is your internet line or router.")
        XCTAssertEqual(good?.severity, .high)
        let weak = diag(wifi: wifi(-85), speed: speed(6)).first { $0.kind == .slowLine }
        XCTAssertEqual(weak?.detail, "Weak Wi-Fi may be part of it.")
        XCTAssertEqual(diag(link: .ethernet, wifi: nil, speed: speed(6)).first?.detail,
                       "Your wired connection is fine, so the slowdown is your internet line or router.")
    }

    func testLaggy() {
        let f = diag(speed: speed(300, rpm: 200)).first { $0.kind == .laggy }
        XCTAssertEqual(f?.headline, "Your connection gets laggy when it's busy.")
        XCTAssertEqual(f?.severity, .medium)
    }

    func testBandwidthHog() {
        let f = InternetDiagnosis.run(link: .wifi, wifi: wifi(-55), speed: nil,
                                      usage: [NetUsage(pid: 640, name: "bird", bytesInPerSec: 200_000, bytesOutPerSec: 2_000_000)],
                                      appName: { $0 == 640 ? "iCloud Drive" : nil })
        XCTAssertEqual(f.map(\.kind), [.bandwidthHog])
        XCTAssertTrue(f[0].headline.hasPrefix("iCloud Drive is using "), f[0].headline)
        XCTAssertTrue(f[0].headline.hasSuffix("/s of your connection."), f[0].headline)
    }

    func testHealthyIsEmpty() {
        XCTAssertEqual(diag(speed: speed(300)), [])
    }

    func testLiveLinkDoesNotCrash() async {
        _ = LinkReader.wifi()
        _ = await LinkReader.currentType()
    }
}
