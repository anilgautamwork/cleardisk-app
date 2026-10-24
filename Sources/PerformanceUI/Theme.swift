import PerformanceCore
import SwiftUI

/// Quiet dark surfaces with readable secondary text and violet actions.
enum Theme {
    static let window = Color(hex: 0x111115)
    static let sidebar = Color(hex: 0x14141A)
    static let card = Color(hex: 0x1D1D25)
    static let raised = Color(hex: 0x252530)
    static let line = Color(hex: 0x343440)
    static let text = Color(hex: 0xF2F2F5)
    static let text2 = Color(hex: 0xB0ACB9)
    static let text3 = Color(hex: 0x97919F)
    static let accent = Color(hex: 0x8155D9)
    static let accentLight = Color(hex: 0xBBA1FF)
    static let button = Color(hex: 0x8155D9)
    static let accentBG = Color(hex: 0x2A2144)
    static let amber = Color(hex: 0xF5B841)
    static let amberBG = Color(hex: 0x3A2E14)
    static let green = Color(hex: 0x6EE7B7)
    static let greenBG = Color(hex: 0x14332A)
    static let red = Color(hex: 0xF87171)
    static let redBG = Color(hex: 0x3A1C1F)
    static let controlBorder = Color(hex: 0x48434F)
    static let mono = Font.system(size: 13.5, design: .monospaced)

    static func color(_ status: Status) -> Color {
        switch status {
        case .quiet: green
        case .busy: amber
        case .struggling: red
        }
    }

    static func color(_ severity: Severity) -> Color {
        severity >= .high ? red : amber
    }

    static func color(_ thermal: Thermal) -> Color {
        switch thermal {
        case .normal: green
        case .warm: amber
        case .hot, .veryHot: red
        }
    }

    static func color(_ pressure: Pressure) -> Color {
        switch pressure {
        case .normal: green
        case .elevated: amber
        case .critical: red
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Status {
    var pillLabel: String {
        switch self {
        case .quiet: "All quiet"
        case .busy: "Busy"
        case .struggling: "Struggling"
        }
    }
}

extension FindingKind {
    var symbol: String {
        switch self {
        case .heat: "thermometer.medium"
        case .memory: "memorychip"
        case .cpuHog: "cpu"
        case .spotlight: "magnifyingglass"
        case .photos: "photo"
        case .windowServer: "macwindow.on.rectangle"
        case .browser: "globe"
        case .lowDisk: "internaldrive"
        case .longUptime: "clock.arrow.circlepath"
        case .lowPower: "battery.25"
        case .stuckApp: "exclamationmark.octagon"
        case .offline: "wifi.slash"
        case .weakWiFi, .band24: "wifi.exclamationmark"
        case .slowLine: "speedometer"
        case .laggy: "waveform.path.ecg"
        case .bandwidthHog: "arrow.up.arrow.down"
        }
    }
}
